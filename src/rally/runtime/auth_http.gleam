@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/bytes_tree
@target(erlang)
import gleam/http/request.{type Request}
@target(erlang)
import gleam/http/response
@target(erlang)
import gleam/io
@target(erlang)
import gleam/list
@target(erlang)
import gleam/string
@target(erlang)
import gleam/uri
@target(erlang)
import mist.{type Connection, type ResponseData}
@target(erlang)
import rally/runtime/session

@target(javascript)
pub fn ensure() -> Nil {
  Nil
}

@target(erlang)
pub fn read_sign_in_form(
  req req: Request(Connection),
  invalid_return_to invalid_return_to: String,
) -> Result(List(#(String, String)), response.Response(ResponseData)) {
  case mist.read_body(req, max_body_limit: 4096) {
    Ok(req_with_body) ->
      case bit_array.to_string(req_with_body.body) {
        Ok(body) ->
          case uri.parse_query(body) {
            Ok(pairs) -> Ok(pairs)
            Error(Nil) -> Error(invalid_sign_in_redirect(invalid_return_to))
          }
        Error(Nil) -> Error(invalid_sign_in_redirect(invalid_return_to))
      }
    Error(error) -> {
      io.println_error(
        "auth: failed to read sign-in body: " <> string.inspect(error),
      )
      Error(invalid_sign_in_redirect(invalid_return_to))
    }
  }
}

@target(erlang)
pub fn sign_out(
  req req: Request(Connection),
  default_return_to default_return_to: String,
  secure secure: Bool,
) -> response.Response(ResponseData) {
  let path = case request.get_query(req) {
    Ok(pairs) ->
      form_value(pairs, "return_to")
      |> safe_local_path(default: default_return_to)
    Error(Nil) -> default_return_to
  }

  redirect(path)
  |> response.expire_cookie(
    session.auth_cookie_name,
    session.auth_cookie_attributes(secure: secure),
  )
}

@target(erlang)
pub fn sign_in_redirect(return_to: String) -> response.Response(ResponseData) {
  redirect("/sign_in?return_to=" <> uri.percent_encode(return_to))
}

@target(erlang)
pub fn invalid_sign_in_redirect(
  return_to: String,
) -> response.Response(ResponseData) {
  redirect(
    "/sign_in?return_to=" <> uri.percent_encode(return_to) <> "&error=invalid",
  )
}

@target(erlang)
pub fn issue_user_session(
  session session: session.AuthSession,
  return_to return_to: String,
  user_id user_id: Int,
  secure secure: Bool,
) -> response.Response(ResponseData) {
  case session.encode_user_id(user_id: user_id, session: session) {
    Ok(encoded) ->
      redirect(return_to)
      |> response.set_cookie(
        session.auth_cookie_name,
        encoded,
        session.auth_cookie_attributes(secure: secure),
      )
    Error(Nil) ->
      response.new(500)
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string("Cannot issue session")),
      )
  }
}

@target(erlang)
pub fn form_value(
  pairs: List(#(String, String)),
  name: String,
) -> Result(String, Nil) {
  list.find_map(pairs, fn(pair) {
    case pair.0 {
      key if key == name -> Ok(pair.1)
      _ -> Error(Nil)
    }
  })
}

@target(erlang)
pub fn safe_local_path(
  path: Result(String, Nil),
  default default: String,
) -> String {
  case path {
    Ok(value) ->
      case string.starts_with(value, "/"), string.starts_with(value, "//") {
        True, False -> value
        _, _ -> default
      }
    Error(Nil) -> default
  }
}

@target(erlang)
fn redirect(path: String) -> response.Response(ResponseData) {
  response.new(302)
  |> response.set_header("location", path)
  |> response.set_body(mist.Bytes(bytes_tree.from_string("")))
}
