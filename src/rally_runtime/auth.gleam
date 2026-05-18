//// Auth types and helpers.
////
//// Page modules use `AuthPolicy` values with `pub const page_auth`, and SSR
//// load functions return `LoadResult` values when auth is enabled.
//// App-specific identity functions such as resolve, is_authenticated, and
//// authorize are still defined per namespace by the app.
////
//// Rally also provides auth secret helpers for hashing and verifying stored
//// secrets, plus short login-code helpers for passwordless sign-in flows.

import argus
import gleam/crypto
import gleam/string

const login_code_alphabet = "23456789abcdefghjkmnpqrstuvwxyz"

const login_code_length = 5

/// Per-page auth policy, declared as `pub const page_auth` in page modules.
/// Required: the user must be authenticated to view the page.
/// Optional: identity is resolved if available, but the page loads either way.
pub type AuthPolicy {
  Required
  Optional
}

/// Return type for auth-enabled `load` functions.
/// Page: render the page with data and optionally set/clear cookies.
/// Redirect: send the user elsewhere (e.g., after login or permission failure).
pub type LoadResult(data) {
  Page(data: data, cookies: List(Cookie))
  Redirect(url: String, cookies: List(Cookie))
}

/// A cookie to set or clear in the SSR response.
pub type Cookie {
  SetCookie(name: String, value: String, max_age: Int)
  ClearCookie(name: String)
}

/// Hash an auth secret for storage.
///
/// This is intended for secrets that will be checked later, such as passwords
/// or short login codes. It uses Argus with a fresh salt.
pub fn hash(secret secret: String) -> String {
  let assert Ok(hashes) =
    argus.hasher()
    |> argus.hash(secret, argus.gen_salt())
  hashes.encoded_hash
}

/// Check a submitted auth secret against a stored hash.
pub fn verify(stored stored: String, secret secret: String) -> Bool {
  case argus.verify(stored, secret) {
    Ok(True) -> True
    _ -> False
  }
}

/// Generate a short, human-friendly login code.
///
/// These codes are meant for short-lived login flows, not long-lived session
/// tokens or API tokens.
pub fn generate_login_code() -> String {
  let alphabet_size = string.length(login_code_alphabet)
  let rejection_threshold = 256 / alphabet_size * alphabet_size
  crypto.strong_random_bytes(16)
  |> pick_login_code_chars(
    alphabet_size:,
    rejection_threshold:,
    needed: login_code_length,
    accumulator: "",
  )
}

/// Hash a scoped login code for storage.
///
/// The scope is usually an email address or other lookup value. Rally
/// normalizes the scope and code before hashing.
pub fn hash_login_code(scope scope: String, code code: String) -> String {
  hash(secret: login_code_secret(scope:, code:))
}

/// Check a submitted login code against a stored hash.
pub fn verify_login_code(
  stored stored: String,
  scope scope: String,
  code code: String,
) -> Bool {
  verify(stored:, secret: login_code_secret(scope:, code:))
}

fn login_code_secret(scope scope: String, code code: String) -> String {
  normalize(scope) <> ":" <> normalize(code)
}

fn normalize(value value: String) -> String {
  value
  |> string.trim
  |> string.lowercase
}

fn pick_login_code_chars(
  bytes bytes: BitArray,
  alphabet_size alphabet_size: Int,
  rejection_threshold rejection_threshold: Int,
  needed needed: Int,
  accumulator accumulator: String,
) -> String {
  case needed, bytes {
    0, _ -> accumulator

    _, <<byte_value, rest:bits>> ->
      case byte_value >= rejection_threshold {
        True ->
          pick_login_code_chars(
            bytes: rest,
            alphabet_size:,
            rejection_threshold:,
            needed:,
            accumulator:,
          )
        False -> {
          let index = byte_value % alphabet_size
          let char = string.slice(login_code_alphabet, index, 1)
          pick_login_code_chars(
            bytes: rest,
            alphabet_size:,
            rejection_threshold:,
            needed: needed - 1,
            accumulator: accumulator <> char,
          )
        }
      }

    _, _ ->
      crypto.strong_random_bytes(16)
      |> pick_login_code_chars(
        alphabet_size:,
        rejection_threshold:,
        needed:,
        accumulator:,
      )
  }
}
