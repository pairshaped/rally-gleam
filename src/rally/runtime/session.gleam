import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/string

@target(erlang)
import gleam/http/cookie
@target(erlang)
import gleam/int
@target(erlang)
import gleam/io
@target(erlang)
import gleam/option.{None, Some}
@target(erlang)
import gleam/result
@target(erlang)
import rally/runtime/env

@target(erlang)
pub const auth_cookie_name = "__rally_auth"

@target(erlang)
const auth_session_aad = "__rally_auth:v1"

@target(erlang)
const auth_session_version = "v1"

@target(erlang)
pub type AuthSession {
  AuthSession(key: BitArray)
}

@target(erlang)
pub type AuthSessionConfigError {
  MissingSecretKey(env_var: String)
  InvalidSecretKeyEncoding(env_var: String)
  InvalidSecretKeyLength(env_var: String, bytes: Int)
}

@target(erlang)
type Encrypted {
  Encrypted(iv: BitArray, ciphertext: BitArray, tag: BitArray)
}

/// Generate a cryptographically random session ID (128-bit hex).
pub fn generate_id() -> String {
  crypto.strong_random_bytes(16)
  |> bit_array.base16_encode()
  |> string.lowercase()
}

/// Extract the rally_session cookie value from a cookie header string.
pub fn extract_session_id(cookie_header: String) -> Result(String, Nil) {
  cookie_header
  |> string.split(";")
  |> list.map(string.trim)
  |> list.find_map(fn(pair) {
    case string.split_once(pair, "=") {
      Ok(#("rally_session", value)) -> {
        let session_id = string.trim(value)
        case session_id {
          "" -> Error(Nil)
          _ -> Ok(session_id)
        }
      }
      _ -> Error(Nil)
    }
  })
}

// HttpOnly: JS can't read the cookie (XSS protection).
// SameSite=Lax (not Strict): allows top-level navigations from external
// links to carry the session, which Strict would block.
pub fn set_cookie_header(
  session_id session_id: String,
  secure secure: Bool,
) -> String {
  "rally_session="
  <> session_id
  <> "; Path=/; HttpOnly; SameSite=Lax"
  <> case secure {
    True -> "; Secure"
    False -> ""
  }
}

@target(erlang)
pub fn new_auth_session(key: BitArray) -> AuthSession {
  AuthSession(key:)
}

@target(erlang)
pub fn auth_session_from_env(
  env_var env_var: String,
  allow_missing_development_key allow_missing_development_key: Bool,
) -> Result(AuthSession, AuthSessionConfigError) {
  case env.get(env_var) {
    Ok(encoded) -> {
      use key <- result.try(decode_auth_session_key(encoded, env_var))
      Ok(new_auth_session(key))
    }
    Error(Nil) ->
      case allow_missing_development_key {
        True -> {
          io.println_error(
            env_var
            <> " is not set; using an in-memory development auth session key",
          )
          Ok(new_auth_session(crypto.strong_random_bytes(32)))
        }
        False -> Error(MissingSecretKey(env_var))
      }
  }
}

@target(erlang)
pub fn auth_session_config_error_message(
  error: AuthSessionConfigError,
) -> String {
  case error {
    MissingSecretKey(env_var) -> env_var <> " is not set"
    InvalidSecretKeyEncoding(env_var) -> env_var <> " must be valid base64"
    InvalidSecretKeyLength(env_var, bytes) ->
      env_var
      <> " must decode to exactly 32 bytes, got "
      <> int.to_string(bytes)
  }
}

@target(erlang)
pub fn find_auth_cookie(
  cookies: List(#(String, String)),
) -> Result(String, Nil) {
  list.find_map(cookies, fn(pair) {
    case pair.0 {
      name if name == auth_cookie_name -> Ok(pair.1)
      _ -> Error(Nil)
    }
  })
}

@target(erlang)
pub fn auth_cookie_attributes(secure secure: Bool) -> cookie.Attributes {
  cookie.Attributes(
    max_age: None,
    domain: None,
    path: Some("/"),
    secure: secure,
    http_only: True,
    same_site: Some(cookie.Lax),
  )
}

@target(erlang)
pub fn encode_user_id(
  user_id user_id: Int,
  session session: AuthSession,
) -> Result(String, Nil) {
  encode_auth_payload(
    payload: "v=1&user_id=" <> int.to_string(user_id),
    session: session,
  )
}

@target(erlang)
pub fn decode_user_id(
  encoded encoded: String,
  session session: AuthSession,
) -> Result(Int, Nil) {
  use payload <- result.try(decode_auth_payload(
    encoded: encoded,
    session: session,
  ))
  use pairs <- result.try(parse_query(payload))
  use _ <- result.try(require_version(pairs))
  use user_id_string <- result.try(list.key_find(pairs, "user_id"))
  int.parse(user_id_string)
}

@target(erlang)
fn decode_auth_session_key(
  encoded: String,
  env_var: String,
) -> Result(BitArray, AuthSessionConfigError) {
  case bit_array.base64_url_decode(encoded) {
    Error(Nil) -> Error(InvalidSecretKeyEncoding(env_var))
    Ok(key) ->
      case bit_array.byte_size(key) {
        32 -> Ok(key)
        bytes -> Error(InvalidSecretKeyLength(env_var, bytes))
      }
  }
}

@target(erlang)
fn encode_auth_payload(
  payload payload: String,
  session session: AuthSession,
) -> Result(String, Nil) {
  let plaintext = bit_array.from_string(payload)
  let aad = bit_array.from_string(auth_session_aad)

  case encrypt(session.key, plaintext, aad) {
    Ok(encrypted) -> {
      let iv_b64 = bit_array.base64_url_encode(encrypted.iv, False)
      let cipher_b64 = bit_array.base64_url_encode(encrypted.ciphertext, False)
      let tag_b64 = bit_array.base64_url_encode(encrypted.tag, False)
      Ok(
        auth_session_version
        <> "."
        <> iv_b64
        <> "."
        <> cipher_b64
        <> "."
        <> tag_b64,
      )
    }
    Error(Nil) -> Error(Nil)
  }
}

@target(erlang)
fn decode_auth_payload(
  encoded encoded: String,
  session session: AuthSession,
) -> Result(String, Nil) {
  case string.split(encoded, ".") {
    [version, iv_b64, cipher_b64, tag_b64] if version == auth_session_version -> {
      use iv <- result.try(bit_array.base64_url_decode(iv_b64))
      use ciphertext <- result.try(bit_array.base64_url_decode(cipher_b64))
      use tag <- result.try(bit_array.base64_url_decode(tag_b64))
      let aad = bit_array.from_string(auth_session_aad)
      let data = Encrypted(iv:, ciphertext:, tag:)
      use plaintext <- result.try(decrypt(session.key, data, aad))
      bit_array.to_string(plaintext)
    }
    _ -> Error(Nil)
  }
}

@target(erlang)
fn parse_query(query: String) -> Result(List(#(String, String)), Nil) {
  case query {
    "" -> Ok([])
    _ ->
      query
      |> string.split("&")
      |> list.map(fn(pair) {
        case string.split(pair, "=") {
          [key, value] -> Ok(#(key, value))
          _ -> Error(Nil)
        }
      })
      |> result.all
  }
}

@target(erlang)
fn require_version(pairs: List(#(String, String))) -> Result(Nil, Nil) {
  case list.key_find(pairs, "v") {
    Ok("1") -> Ok(Nil)
    _ -> Error(Nil)
  }
}

@target(erlang)
@external(erlang, "rally_runtime_session_ffi", "encrypt")
fn encrypt(
  key: BitArray,
  plaintext: BitArray,
  aad: BitArray,
) -> Result(Encrypted, Nil)

@target(erlang)
@external(erlang, "rally_runtime_session_ffi", "decrypt")
fn decrypt(
  key: BitArray,
  encrypted: Encrypted,
  aad: BitArray,
) -> Result(BitArray, Nil)
