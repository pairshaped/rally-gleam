import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/string

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
