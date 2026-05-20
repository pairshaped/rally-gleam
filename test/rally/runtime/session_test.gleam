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
