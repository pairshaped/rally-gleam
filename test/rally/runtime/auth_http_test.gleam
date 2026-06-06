import gleam/bit_array
import gleam/bytes_tree
import gleam/http
import gleam/http/request
import gleam/http/response.{Response}
import gleam/int
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

pub fn code_sent_redirect_sets_sent_query_test() {
  auth_http.code_sent_redirect("/admin/games")
  |> response.get_header("location")
  |> should.equal(Ok("/sign_in?return_to=%2Fadmin%2Fgames&sent=1"))
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

pub fn start_google_sign_in_redirects_to_google_and_sets_state_cookie_test() {
  let resp =
    request.new()
    |> request.set_query([#("return_to", "/admin/games")])
    |> auth_http.start_google_sign_in(
      credentials: auth_http.GoogleCredentials(
        client_id: "google-client",
        redirect_uri: "https://app.test/sign_in/google/callback",
      ),
      default_return_to: "/games",
      return_to: fn(path) { path },
      secure: False,
    )

  let assert Ok(location) = response.get_header(resp, "location")
  location
  |> string.starts_with("https://accounts.google.com/o/oauth2/v2/auth?")
  |> should.be_true()
  location
  |> string.contains("client_id=google-client")
  |> should.be_true()
  location
  |> string.contains(
    "redirect_uri=https%3A%2F%2Fapp.test%2Fsign_in%2Fgoogle%2Fcallback",
  )
  |> should.be_true()
  location
  |> string.contains("scope=openid%20email%20profile")
  |> should.be_true()

  let assert Response(headers:, body: mist.Bytes(_), status: 302) = resp
  let headers = string.inspect(headers)
  headers
  |> string.contains("__rally_google_state")
  |> should.be_true()
  headers
  |> string.contains("__rally_google_return_to")
  |> should.be_true()
}

pub fn route_google_auth_returns_503_when_google_is_not_configured_test() {
  let resp =
    request.new()
    |> request.set_method(http.Get)
    |> request.set_path("/sign_in/google")
    |> auth_http.route_google_auth(
      context: Nil,
      routes: auth_http.GoogleAuthRoutes(
        session: fn(_context) { session.new_auth_session(test_key()) },
        credentials: fn(_context) { Error(Nil) },
        sign_in: fn(_code, _context) { Error(Nil) },
        sign_in_default_return_to: "/games",
        sign_in_return_to: fn(path) { path },
        secure: False,
      ),
    )

  let assert Ok(resp) = resp
  resp
  |> should.equal(auth_http.google_not_configured_response())
}

pub fn finish_google_sign_in_issues_session_when_state_matches_test() {
  let resp =
    request.new()
    |> request.set_query([#("code", "provider-code"), #("state", "state-123")])
    |> request.set_header(
      "cookie",
      "__rally_google_state=state-123; __rally_google_return_to=/admin/games",
    )
    |> auth_http.finish_google_sign_in(
      session: session.new_auth_session(test_key()),
      sign_in: fn(code) {
        case code {
          "provider-code" -> Ok(7)
          _ -> Error(Nil)
        }
      },
      default_return_to: "/games",
      return_to: fn(path) { path },
      secure: False,
    )

  response.get_header(resp, "location")
  |> should.equal(Ok("/admin/games"))

  let assert Response(headers:, body: mist.Bytes(_), status: 302) = resp
  let headers = string.inspect(headers)
  headers
  |> string.contains(session.auth_cookie_name)
  |> should.be_true()
  headers
  |> string.contains("__rally_google_state=;")
  |> should.be_true()
  headers
  |> string.contains("__rally_google_return_to=;")
  |> should.be_true()
}

pub fn finish_google_sign_in_rejects_state_mismatch_test() {
  let resp =
    request.new()
    |> request.set_query([#("code", "provider-code"), #("state", "state-123")])
    |> request.set_header(
      "cookie",
      "__rally_google_state=other-state; __rally_google_return_to=/admin/games",
    )
    |> auth_http.finish_google_sign_in(
      session: session.new_auth_session(test_key()),
      sign_in: fn(_code) { Ok(7) },
      default_return_to: "/games",
      return_to: fn(path) { path },
      secure: False,
    )

  response.get_header(resp, "location")
  |> should.equal(Ok("/sign_in?return_to=%2Fadmin%2Fgames&error=invalid"))

  let assert Response(headers:, body: mist.Bytes(_), status: 302) = resp
  let headers = string.inspect(headers)
  headers
  |> string.contains(session.auth_cookie_name)
  |> should.be_false()
  headers
  |> string.contains("__rally_google_state=;")
  |> should.be_true()
  headers
  |> string.contains("__rally_google_return_to=;")
  |> should.be_true()
}

pub fn authenticated_user_decodes_cookie_and_loads_user_test() {
  let auth_session = session.new_auth_session(test_key())
  let assert Ok(encoded) =
    session.encode_user_id(user_id: 7, session: auth_session)
  let auth =
    auth_http.RequestAuth(
      session: auth_session,
      load_user: fn(user_id) { Ok("user:" <> int_to_string(user_id)) },
      can_access: fn(_user) { True },
    )

  request.new()
  |> request.set_header("cookie", session.auth_cookie_name <> "=" <> encoded)
  |> auth_http.authenticated_user(auth:)
  |> should.equal(Ok("user:7"))
}

pub fn authorized_user_rejects_failed_access_policy_test() {
  let auth_session = session.new_auth_session(test_key())
  let assert Ok(encoded) =
    session.encode_user_id(user_id: 7, session: auth_session)
  let auth =
    auth_http.RequestAuth(
      session: auth_session,
      load_user: fn(_user_id) { Ok("user") },
      can_access: fn(_user) { False },
    )

  request.new()
  |> request.set_header("cookie", session.auth_cookie_name <> "=" <> encoded)
  |> auth_http.authorized_user(auth:)
  |> should.equal(Error(Nil))
}

pub fn protect_redirects_to_sign_in_when_access_fails_test() {
  let auth =
    auth_http.RequestAuth(
      session: session.new_auth_session(test_key()),
      load_user: fn(_user_id) { Error(Nil) },
      can_access: fn(_user) { True },
    )

  let resp =
    request.new()
    |> request.set_path("/admin/games")
    |> auth_http.protect(auth:, render: fn(_user) {
      response.new(200)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("ok")))
    })

  response.get_header(resp, "location")
  |> should.equal(Ok("/sign_in?return_to=%2Fadmin%2Fgames"))
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

fn int_to_string(value: Int) -> String {
  value |> int.to_string
}
