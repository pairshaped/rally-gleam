import gleam/list
import gleam/string
import gleeunit/should
import rally_runtime/auth

const login_code_alphabet = "23456789abcdefghjkmnpqrstuvwxyz"

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
    auth.hash_login_code(scope: " TEST@example.COM ", code: " AbC23 ")

  auth.verify_login_code(stored:, scope: "test@example.com", code: "abc23")
  |> should.be_true
}

pub fn login_code_verify_rejects_wrong_scope_test() {
  let stored = auth.hash_login_code(scope: "first@example.com", code: "abc23")

  auth.verify_login_code(stored:, scope: "second@example.com", code: "abc23")
  |> should.be_false
}

pub fn login_code_verify_rejects_wrong_code_test() {
  let stored = auth.hash_login_code(scope: "test@example.com", code: "abc23")

  auth.verify_login_code(stored:, scope: "test@example.com", code: "xyz89")
  |> should.be_false
}
