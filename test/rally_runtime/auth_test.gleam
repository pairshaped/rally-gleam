import gleam/list
import gleam/string
import gleeunit/should
import rally_runtime/auth

const login_code_alphabet = "23456789abcdefghjkmnpqrstuvwxyz"

const login_code_secret_key = "test-secret-key"

pub fn hash_and_verify_secret_test() {
  let stored = auth.hash(secret: "correct horse")

  auth.verify(stored:, secret: "correct horse")
  |> should.be_true
}

pub fn verify_rejects_wrong_secret_test() {
  let stored = auth.hash(secret: "correct horse")

  auth.verify(stored:, secret: "wrong horse")
  |> should.be_false
}

pub fn hash_uses_fresh_salt_test() {
  let first = auth.hash(secret: "same secret")
  let second = auth.hash(secret: "same secret")

  should.not_equal(first, second)
}

pub fn generate_login_code_returns_five_friendly_chars_test() {
  let code = auth.generate_login_code()

  code
  |> string.length
  |> should.equal(5)

  code
  |> string.to_graphemes
  |> list.all(fn(char) { string.contains(login_code_alphabet, char) })
  |> should.be_true
}

pub fn login_code_hash_normalizes_scope_and_code_test() {
  let stored =
    auth.hash_login_code(
      scope: " TEST@example.COM ",
      code: " AbC23 ",
      secret_key: login_code_secret_key,
    )

  auth.verify_login_code(
    stored:,
    scope: "test@example.com",
    code: "abc23",
    secret_key: login_code_secret_key,
  )
  |> should.be_true
}

pub fn login_code_verify_rejects_wrong_scope_test() {
  let stored =
    auth.hash_login_code(
      scope: "first@example.com",
      code: "abc23",
      secret_key: login_code_secret_key,
    )

  auth.verify_login_code(
    stored:,
    scope: "second@example.com",
    code: "abc23",
    secret_key: login_code_secret_key,
  )
  |> should.be_false
}

pub fn login_code_verify_rejects_wrong_code_test() {
  let stored =
    auth.hash_login_code(
      scope: "test@example.com",
      code: "abc23",
      secret_key: login_code_secret_key,
    )

  auth.verify_login_code(
    stored:,
    scope: "test@example.com",
    code: "xyz89",
    secret_key: login_code_secret_key,
  )
  |> should.be_false
}

pub fn login_code_verify_rejects_wrong_secret_key_test() {
  let stored =
    auth.hash_login_code(
      scope: "test@example.com",
      code: "abc23",
      secret_key: login_code_secret_key,
    )

  auth.verify_login_code(
    stored:,
    scope: "test@example.com",
    code: "abc23",
    secret_key: "different-secret-key",
  )
  |> should.be_false
}

pub fn login_code_hash_uses_hmac_format_test() {
  let stored =
    auth.hash_login_code(
      scope: "test@example.com",
      code: "abc23",
      secret_key: login_code_secret_key,
    )

  stored
  |> string.starts_with("$rally-login-code-hmac-sha256$v=1$")
  |> should.be_true
}

pub fn try_hash_returns_ok_on_normal_input_test() {
  let assert Ok(hashed) = auth.try_hash(secret: "a secret")

  hashed
  |> string.starts_with("$rally-pbkdf2-sha256$v=1$i=600000$")
  |> should.be_true

  auth.verify(stored: hashed, secret: "a secret")
  |> should.be_true
}

pub fn verify_rejects_malformed_hash_test() {
  auth.verify(stored: "$argon2id$v=19$m=19456,t=2,p=1$old", secret: "a secret")
  |> should.be_false
}

pub fn try_hash_login_code_returns_ok_and_verifies_test() {
  let assert Ok(stored) =
    auth.try_hash_login_code(
      scope: "test@example.com",
      code: "abc23",
      secret_key: login_code_secret_key,
    )

  auth.verify_login_code(
    stored:,
    scope: "test@example.com",
    code: "abc23",
    secret_key: login_code_secret_key,
  )
  |> should.be_true
}
