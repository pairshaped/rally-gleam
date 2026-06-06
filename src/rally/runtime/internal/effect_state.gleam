//// Internal WebSocket process state and push-frame helpers.
////
//// Generated handlers use this module to coordinate connection state,
//// auth state, and outgoing frames. Page modules should import
//// rally/runtime/effect instead.

/// Store the WS connection handle, load context, and current page name.
@external(erlang, "rally_runtime_ffi", "put_ws_state")
pub fn put_ws_state(_conn: a, _load_context: b, _page: String) -> Nil {
  Nil
}

/// Get the current page name for this WS connection.
@external(erlang, "rally_runtime_ffi", "get_ws_page")
pub fn get_ws_page() -> String {
  ""
}

/// Get the mist connection handle for this WS process.
@external(erlang, "rally_runtime_ffi", "get_ws_conn")
pub fn get_ws_conn() -> Result(a, Nil) {
  Error(Nil)
}

@external(erlang, "rally_runtime_ffi", "push_outgoing_frame")
pub fn push_outgoing_frame(_frame: a) -> Nil {
  Nil
}

/// Drain all queued push frames. Called by the WS handler after dispatch.
@external(erlang, "rally_runtime_ffi", "drain_outgoing_frames")
pub fn drain_outgoing_frames() -> List(a) {
  []
}

/// Store the session ID on the current WS process.
@external(erlang, "rally_runtime_ffi", "put_ws_session")
pub fn put_ws_session(_session_id: String) -> Nil {
  Nil
}

/// Get the session ID for the current WS connection.
@external(erlang, "rally_runtime_ffi", "get_ws_session")
pub fn get_ws_session() -> String {
  ""
}

/// Decode an inbound push frame (ETF protocol).
@external(erlang, "rally_runtime_ffi", "decode_rally_push")
pub fn decode_rally_push(_msg: a) -> Result(BitArray, Nil) {
  Error(Nil)
}

/// Decode an inbound push frame (JSON protocol).
@external(erlang, "rally_runtime_ffi", "decode_rally_push_json")
pub fn decode_rally_push_json(_msg: a) -> Result(String, Nil) {
  Error(Nil)
}

/// Encode a value as a push frame tagged with a page name.
@external(erlang, "rally_runtime_ffi", "encode_push_frame")
pub fn encode_push_frame(_page: String, msg: a) -> a {
  msg
}

/// Store the resolved identity on the WebSocket connection process.
/// The identity type is opaque to Rally; it's stored as an Erlang term.
@external(erlang, "rally_runtime_ffi", "put_ws_identity")
pub fn put_ws_identity(_identity: a) -> Nil {
  Nil
}

/// Retrieve the stored identity. Returns Error(Nil) when no identity
/// has been stored (fresh process or pre-auth connection).
@external(erlang, "rally_runtime_ffi", "get_ws_identity")
pub fn get_ws_identity() -> Result(a, Nil) {
  Error(Nil)
}

/// Store the hostname extracted during WebSocket upgrade.
@external(erlang, "rally_runtime_ffi", "put_ws_hostname")
pub fn put_ws_hostname(_hostname: String) -> Nil {
  Nil
}

/// Retrieve the stored hostname. Returns "" when not set.
@external(erlang, "rally_runtime_ffi", "get_ws_hostname")
pub fn get_ws_hostname() -> String {
  ""
}

/// Store the Unix timestamp of the last successful auth check.
@external(erlang, "rally_runtime_ffi", "put_ws_auth_timestamp")
pub fn put_ws_auth_timestamp(_ts: Int) -> Nil {
  Nil
}

/// Retrieve the auth timestamp. Returns 0 when not set.
@external(erlang, "rally_runtime_ffi", "get_ws_auth_timestamp")
pub fn get_ws_auth_timestamp() -> Int {
  0
}

/// Clear identity and reset timestamp to 0. Hostname is preserved.
@external(erlang, "rally_runtime_ffi", "clear_ws_auth_state")
pub fn clear_ws_auth_state() -> Nil {
  Nil
}
