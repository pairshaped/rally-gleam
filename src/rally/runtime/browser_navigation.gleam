//// Rally-owned browser navigation policy.
////
//// Modem owns URL change messages and browser history listeners. Rally owns
//// which links are eligible for SPA navigation before history is pushed.

import gleam/option.{None, Some}
import gleam/uri.{type Uri}
import lustre/effect.{type Effect}
import modem

/// Listen for browser-owned URL changes.
///
/// Same-origin link clicks are disabled here. Rally's generated runtime installs
/// a separate mount-aware link listener so app pages do not need to undo broad
/// same-origin interception after it has already happened.
pub fn listen_browser_navigation(to_message: fn(String) -> msg) -> Effect(msg) {
  modem.advanced(
    modem.Options(handle_internal_links: False, handle_external_links: False),
    fn(location) { to_message(path_from_uri(location)) },
  )
}

/// Listen for normal same-mount document links.
///
/// Same-origin links in the current mount are SPA navigations by default. Links
/// that switch mounts, such as public to admin, are left alone so the browser
/// loads the correct entrypoint. Add `data-rally-document-nav` when an otherwise
/// interceptable link should force a document navigation.
pub fn listen_shell_navigation(to_message: fn(String) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch) {
    do_listen_shell_navigation(fn(path) { dispatch(to_message(path)) })
  })
}

/// Push a URL after Rally has already handled the navigation.
///
/// This intentionally does not use `modem.push`, which emits a URL-change event.
/// Generated Rally mounts have already loaded the target page by the time they
/// call this function.
pub fn push_path(path: String) -> Effect(msg) {
  effect.from(fn(_dispatch) { do_push_path(path) })
}

/// Push a URL and notify browser navigation listeners.
pub fn navigate(path: String) -> Effect(msg) {
  effect.from(fn(_dispatch) { do_navigate(path) })
}

fn path_from_uri(location: Uri) -> String {
  let path = case location.path {
    "" -> "/"
    path -> path
  }

  case location.query {
    Some(query) -> path <> "?" <> query
    None -> path
  }
}

@external(javascript, "./browser_navigation_ffi.mjs", "listen_shell_navigation")
fn do_listen_shell_navigation(_dispatch: fn(String) -> Nil) -> Nil {
  Nil
}

@external(javascript, "./browser_navigation_ffi.mjs", "push_path")
fn do_push_path(_path: String) -> Nil {
  Nil
}

@external(javascript, "./browser_navigation_ffi.mjs", "navigate")
fn do_navigate(_path: String) -> Nil {
  Nil
}
