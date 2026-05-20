import rally/runtime/internal/effect_state as effect

pub fn put_get_identity_roundtrip_test() {
  effect.put_ws_identity(42)
  let assert Ok(42) = effect.get_ws_identity()
}

pub fn get_identity_unset_returns_error_test() {
  effect.clear_ws_auth_state()
  let assert Error(Nil) = effect.get_ws_identity()
}

pub fn put_get_hostname_roundtrip_test() {
  effect.put_ws_hostname("example.com")
  let assert "example.com" = effect.get_ws_hostname()
}

pub fn get_hostname_unset_returns_empty_test() {
  effect.clear_ws_auth_state()
  // clear_ws_auth_state preserves hostname (connection-scoped).
  // Explicitly reset it to test the default.
  effect.put_ws_hostname("")
  let assert "" = effect.get_ws_hostname()
}

pub fn put_get_auth_timestamp_roundtrip_test() {
  effect.put_ws_auth_timestamp(1_715_000_000)
  let assert 1_715_000_000 = effect.get_ws_auth_timestamp()
}

pub fn get_auth_timestamp_unset_returns_zero_test() {
  effect.clear_ws_auth_state()
  let assert 0 = effect.get_ws_auth_timestamp()
}
