//// The API that page modules import for server communication, broadcast,
//// and navigation.
////
//// This module has a split personality by design. Each function has two
//// implementations: the server-side version here (which queues push frames
//// via the process dictionary or is a no-op), and a client-side version
//// in the generated rally/runtime/effect.gleam shim (which calls the
//// browser WebSocket transport). The codegen rewrites imports so the
//// client package uses the shim, not this file.
////
//// Two server communication models:
////
////   rpc(msg, on_response:)    Stateless request-response. Define a
////                             ServerX message type and server_x handler.
////                             Client sends, server returns a value.
////                             Use this by default.
////
////   send_to_server(msg)       Stateful bidirectional. Define ToServer/
////                             ToClient types and server_init/server_update.
////                             Server keeps a ServerModel per connection
////                             and can push ToClient messages any time.
////                             Use when the server needs state between calls.

import lustre/effect
import rally/runtime/internal/effect_state
import rally/runtime/topics

pub type Effect(a) =
  effect.Effect(a)

pub fn none() -> Effect(a) {
  effect.none()
}

/// Send a ToServer variant to the server over WebSocket.
/// Part of the stateful model (ToServer/ToClient/ServerModel).
/// On the server this is a no-op. On the client, the generated
/// transport module provides the real implementation.
pub fn send_to_server(_msg: a) -> Effect(b) {
  effect.none()
}

/// Call a server_* RPC handler and deliver the return value to on_response.
/// Part of the stateless RPC model (ServerX type + server_x function).
/// On the server this is a no-op. On the client, the generated transport
/// module encodes the message and sends it over WebSocket.
pub fn rpc(_msg: a, on_response _on_response: fn(b) -> msg) -> Effect(msg) {
  effect.none()
}

/// Send a ToClient variant to the connected client.
/// Encodes the message as a protocol-specific push frame and queues it for
/// the WebSocket handler to send after the current dispatch.
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
    topics.broadcast("page:" <> page, frame)
    effect_state.push_outgoing_frame(frame)
  })
}

/// Broadcast a message to every connection in the app.
pub fn broadcast_to_app(msg: a) -> Effect(b) {
  deferred(fn() {
    let page = effect_state.get_ws_page()
    let frame = encode_push_frame(page, msg)
    topics.broadcast("app", frame)
    effect_state.push_outgoing_frame(frame)
  })
}

/// Send a ClientContextMsg to update the client's shared context.
/// On the server, encodes and queues a push frame tagged "__ClientContext__".
/// On the client, the generated app dispatches it through client_context.update.
pub fn send_to_client_context(msg: a) -> Effect(b) {
  deferred(fn() {
    let frame = encode_push_frame("__ClientContext__", msg)
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
    topics.broadcast("session:" <> session, frame)
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
