//// Page-side effects for navigation, theme preferences, and server-side
//// broadcast fan-out.

import lustre/effect
import rally/runtime/internal/effect_state
import rally/runtime/topics

pub type Effect(a) =
  effect.Effect(a)

pub fn none() -> Effect(a) {
  effect.none()
}

/// Queue a push frame for the current WebSocket connection.
pub fn send_to_client(msg: a) -> Effect(b) {
  deferred(fn() { do_push(msg) })
}

/// Broadcast a message to all connections viewing the current page.
/// Broadcasts via pg topics for other connections, plus push_outgoing_frame
/// for the sender's own connection (which isn't subscribed to its own topic).
pub fn broadcast_to_page(msg: a) -> Effect(b) {
  deferred(fn() {
    let page = effect_state.get_ws_page()
    let frame = encode_push_frame(page, msg)
    let _ = topics.broadcast("page:" <> page, frame)
    effect_state.push_outgoing_frame(frame)
  })
}

/// Broadcast a message to every connection in the app.
pub fn broadcast_to_app(msg: a) -> Effect(b) {
  deferred(fn() {
    let page = effect_state.get_ws_page()
    let frame = encode_push_frame(page, msg)
    let _ = topics.broadcast("app", frame)
    effect_state.push_outgoing_frame(frame)
  })
}

/// Navigate to a new URL path. Pushes a new history entry and triggers
/// a route change via modem's popstate listener.
/// On the server, this is a no-op.
pub fn navigate(path: String) -> Effect(a) {
  effect.from(fn(_dispatch) {
    let Nil = do_navigate(path)
    Nil
  })
}

@external(javascript, "./rally_effect_ffi.mjs", "navigate")
fn do_navigate(_path: String) -> Nil {
  Nil
}

/// Toggle dark mode. On the client, sets the cookie and toggles the class.
/// On the server, this is a no-op.
pub fn set_dark_mode(_enabled: Bool) -> Effect(a) {
  effect.none()
}

/// Set the language preference cookie.
/// On the server, this is a no-op.
pub fn set_lang(_lang: String) -> Effect(a) {
  effect.none()
}

/// Read the dark mode preference from the cookie.
/// Falls back to prefers-color-scheme media query.
/// On the server, returns False.
pub fn read_dark_mode() -> Bool {
  False
}

/// Read the language preference from the cookie.
/// On the server, returns "en".
pub fn read_lang() -> String {
  "en"
}

/// Broadcast a message to all connections in the current browser session.
pub fn broadcast_to_session(msg: a) -> Effect(b) {
  deferred(fn() {
    let page = effect_state.get_ws_page()
    let session = get_ws_session()
    let frame = encode_push_frame(page, msg)
    let _ = topics.broadcast("session:" <> session, frame)
    effect_state.push_outgoing_frame(frame)
  })
}

fn do_push(msg: a) -> Nil {
  let page = effect_state.get_ws_page()
  let frame = encode_push_frame(page, msg)
  effect_state.push_outgoing_frame(frame)
}

/// Get the session ID for the current WS connection.
pub fn get_ws_session() -> String {
  effect_state.get_ws_session()
}

fn encode_push_frame(page: String, msg: a) -> a {
  effect_state.encode_push_frame(page, msg)
}

fn deferred(run: fn() -> Nil) -> Effect(a) {
  effect.from(fn(_dispatch) { run() })
}
