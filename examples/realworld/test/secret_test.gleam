import gleam/string
import gleeunit/should
import rally_runtime/auth

pub fn hash_produces_argon2_string_test() {
  let hashed = auth.hash("mysecret")
  hashed
  |> string.starts_with("$argon2")
  |> should.be_true
}

pub fn verify_correct_secret_test() {
  let hashed = auth.hash("correctsecret")
  auth.verify(hashed, "correctsecret")
  |> should.be_true
}

pub fn verify_wrong_secret_test() {
  let hashed = auth.hash("correctsecret")
  auth.verify(hashed, "wrongsecret")
  |> should.be_false
}

pub fn different_hashes_for_same_secret_test() {
  let hash1 = auth.hash("samesecret")
  let hash2 = auth.hash("samesecret")
  should.not_equal(hash1, hash2)
}
