import gleam/bit_array
import gleam/http/response.{Response}
import gleam/string
import gleeunit/should
import mist
import rally/runtime/auth_http
import rally/runtime/session

pub fn sign_in_redirect_sets_encoded_return_to_test() {
  auth_http.sign_in_redirect("/admin/games")
  |> response.get_header("location")
  |> should.equal(Ok("/sign_in?return_to=%2Fadmin%2Fgames"))
}

pub fn invalid_sign_in_redirect_sets_error_query_test() {
  auth_http.invalid_sign_in_redirect("/admin/games")
  |> response.get_header("location")
  |> should.equal(Ok("/sign_in?return_to=%2Fadmin%2Fgames&error=invalid"))
}

pub fn issue_user_session_sets_auth_cookie_test() {
  let resp =
    auth_http.issue_user_session(
      session: session.new_auth_session(test_key()),
      return_to: "/admin/games",
      user_id: 7,
      secure: False,
    )

  response.get_header(resp, "location")
  |> should.equal(Ok("/admin/games"))

  let assert Response(headers:, body: mist.Bytes(_), status: 302) = resp
  headers
  |> string.inspect
  |> string.contains(session.auth_cookie_name)
  |> should.be_true()
}

pub fn safe_local_path_rejects_external_urls_test() {
  auth_http.safe_local_path(Ok("//evil.test"), default: "/games")
  |> should.equal("/games")
}

pub fn safe_local_path_accepts_absolute_local_urls_test() {
  auth_http.safe_local_path(Ok("/admin/games"), default: "/games")
  |> should.equal("/admin/games")
}

fn test_key() -> BitArray {
  bit_array.from_string("12345678901234567890123456789012")
}
