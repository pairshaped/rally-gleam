import envoy
import gleam/bit_array
import gleam/http/cookie
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import rally/runtime/session

pub fn generate_session_id_test() {
  let id = session.generate_id()
  let assert True = string.length(id) > 0
}

pub fn extract_session_from_cookie_test() {
  let cookie_header = "rally_session=abc123; other=value"
  session.extract_session_id(cookie_header)
  |> should.equal(Ok("abc123"))
}

pub fn extract_session_missing_test() {
  let cookie_header = "other=value"
  session.extract_session_id(cookie_header)
  |> should.equal(Error(Nil))
}

pub fn extract_session_empty_test() {
  session.extract_session_id("")
  |> should.equal(Error(Nil))
}

pub fn extract_session_rejects_empty_cookie_value_test() {
  session.extract_session_id("rally_session=; other=value")
  |> should.equal(Error(Nil))
}

pub fn extract_session_rejects_whitespace_cookie_value_test() {
  session.extract_session_id("rally_session=   ; other=value")
  |> should.equal(Error(Nil))
}

pub fn set_cookie_header_secure_test() {
  session.set_cookie_header(session_id: "abc123", secure: True)
  |> should.equal(
    "rally_session=abc123; Path=/; HttpOnly; SameSite=Lax; Secure",
  )
}

pub fn set_cookie_header_insecure_test() {
  session.set_cookie_header(session_id: "abc123", secure: False)
  |> should.equal("rally_session=abc123; Path=/; HttpOnly; SameSite=Lax")
}

pub fn auth_session_encode_decode_user_id_roundtrip_test() {
  let auth_session = session.new_auth_session(test_key())
  let assert Ok(encoded) =
    session.encode_user_id(user_id: 42, session: auth_session)

  session.decode_user_id(encoded: encoded, session: auth_session)
  |> should.equal(Ok(42))
}

pub fn auth_session_rejects_tampered_cookie_test() {
  let auth_session = session.new_auth_session(test_key())
  let assert Ok(encoded) =
    session.encode_user_id(user_id: 42, session: auth_session)

  session.decode_user_id(encoded: encoded <> "x", session: auth_session)
  |> should.equal(Error(Nil))
}

pub fn find_auth_cookie_test() {
  session.find_auth_cookie([
    #("other", "value"),
    #(session.auth_cookie_name, "encoded"),
  ])
  |> should.equal(Ok("encoded"))
}

pub fn auth_cookie_attributes_are_http_only_test() {
  session.auth_cookie_attributes(secure: True)
  |> should.equal(cookie.Attributes(
    max_age: None,
    domain: None,
    path: Some("/"),
    secure: True,
    http_only: True,
    same_site: Some(cookie.Lax),
  ))
}

pub fn auth_session_from_env_uses_valid_key_test() {
  let env_var = "RALLY_TEST_AUTH_SESSION_KEY"
  envoy.set(env_var, bit_array.base64_url_encode(test_key(), False))

  let assert Ok(auth_session) =
    session.auth_session_from_env(
      env_var: env_var,
      allow_missing_development_key: False,
    )
  let assert Ok(encoded) =
    session.encode_user_id(user_id: 123, session: auth_session)

  session.decode_user_id(encoded: encoded, session: auth_session)
  |> should.equal(Ok(123))
}

pub fn auth_session_from_env_rejects_missing_key_without_fallback_test() {
  session.auth_session_from_env(
    env_var: "RALLY_TEST_AUTH_SESSION_MISSING",
    allow_missing_development_key: False,
  )
  |> should.equal(
    Error(session.MissingSecretKey("RALLY_TEST_AUTH_SESSION_MISSING")),
  )
}

pub fn auth_session_from_env_uses_development_fallback_test() {
  let assert Ok(auth_session) =
    session.auth_session_from_env(
      env_var: "RALLY_TEST_AUTH_SESSION_DEV_MISSING",
      allow_missing_development_key: True,
    )
  let assert Ok(encoded) =
    session.encode_user_id(user_id: 321, session: auth_session)

  session.decode_user_id(encoded: encoded, session: auth_session)
  |> should.equal(Ok(321))
}

pub fn auth_session_from_env_rejects_wrong_length_key_test() {
  let env_var = "RALLY_TEST_AUTH_SESSION_SHORT"
  envoy.set(
    env_var,
    bit_array.base64_url_encode(bit_array.from_string("short"), False),
  )

  session.auth_session_from_env(
    env_var: env_var,
    allow_missing_development_key: False,
  )
  |> should.equal(Error(session.InvalidSecretKeyLength(env_var, 5)))
}

fn test_key() -> BitArray {
  bit_array.from_string("12345678901234567890123456789012")
}
