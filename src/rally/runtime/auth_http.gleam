@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/bytes_tree
@target(erlang)
import gleam/http
@target(erlang)
import gleam/http/request.{type Request}
@target(erlang)
import gleam/http/response
@target(erlang)
import gleam/io
@target(erlang)
import gleam/list
@target(erlang)
import gleam/result
@target(erlang)
import gleam/string
@target(erlang)
import gleam/uri
@target(erlang)
import mist.{type Connection, type ResponseData}
@target(erlang)
import rally/runtime/session

@target(erlang)
pub type RequestAuth(user) {
  RequestAuth(
    session: session.AuthSession,
    load_user: fn(Int) -> Result(user, Nil),
    can_access: fn(user) -> Bool,
  )
}

@target(erlang)
pub type CodeAuthRoutes(context) {
  CodeAuthRoutes(
    session: fn(context) -> session.AuthSession,
    verify_code: fn(String, context) -> Result(Int, Nil),
    deliver_code: fn(String, context) -> Result(Nil, Nil),
    sign_in_default_return_to: String,
    sign_in_return_to: fn(String) -> String,
    sign_out_default_return_to: String,
    secure: Bool,
  )
}

@target(javascript)
pub fn ensure() -> Nil {
  Nil
}

@target(erlang)
pub fn route_code_auth(
  req req: Request(Connection),
  context context: context,
  routes routes: CodeAuthRoutes(context),
) -> Result(response.Response(ResponseData), Nil) {
  case req.method, req.path {
    http.Post, "/sign_in/code" ->
      request_sign_in_code(
        req: req,
        deliver_code: fn(email) { routes.deliver_code(email, context) },
        default_return_to: routes.sign_in_default_return_to,
        return_to: routes.sign_in_return_to,
      )
      |> Ok

    http.Post, "/sign_in" ->
      sign_in_with_code(
        req: req,
        session: routes.session(context),
        verify_code: fn(code) { routes.verify_code(code, context) },
        default_return_to: routes.sign_in_default_return_to,
        return_to: routes.sign_in_return_to,
        secure: routes.secure,
      )
      |> Ok

    http.Get, "/sign_out" ->
      sign_out(
        req: req,
        default_return_to: routes.sign_out_default_return_to,
        secure: routes.secure,
      )
      |> Ok

    http.Post, "/sign_out" ->
      sign_out(
        req: req,
        default_return_to: routes.sign_out_default_return_to,
        secure: routes.secure,
      )
      |> Ok

    _, _ -> Error(Nil)
  }
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
/// Handle the standard email/code request workflow.
/// Rally owns form parsing and redirects; the app owns user lookup, code
/// storage, and delivery through the callback.
pub fn request_sign_in_code(
  req req: Request(Connection),
  deliver_code deliver_code: fn(String) -> Result(Nil, Nil),
  default_return_to default_return_to: String,
  return_to return_to: fn(String) -> String,
) -> response.Response(ResponseData) {
  case read_sign_in_form(req, invalid_return_to: default_return_to) {
    Ok(pairs) -> {
      let return_to =
        form_value(pairs, "return_to")
        |> safe_local_path(default: default_return_to)
        |> return_to

      case form_value(pairs, "email") {
        Ok(email) ->
          case deliver_code(email) {
            Ok(Nil) -> code_sent_redirect(return_to)
            Error(Nil) -> invalid_sign_in_redirect(return_to)
          }
        Error(Nil) -> invalid_sign_in_redirect(return_to)
      }
    }
    Error(response) -> response
  }
}

@target(erlang)
/// Handle the standard email/code sign-in POST workflow.
/// Rally owns form parsing, local return-path safety, invalid redirects, and
/// session issuing. The app supplies credential verification and any product
/// route narrowing for the already-local return path.
pub fn sign_in_with_code(
  req req: Request(Connection),
  session session: session.AuthSession,
  verify_code verify_code: fn(String) -> Result(Int, Nil),
  default_return_to default_return_to: String,
  return_to return_to: fn(String) -> String,
  secure secure: Bool,
) -> response.Response(ResponseData) {
  case read_sign_in_form(req, invalid_return_to: default_return_to) {
    Ok(pairs) -> {
      let return_to =
        form_value(pairs, "return_to")
        |> safe_local_path(default: default_return_to)
        |> return_to

      case form_value(pairs, "code") {
        Ok(code) ->
          case verify_code(code) {
            Ok(user_id) ->
              issue_user_session(
                session: session,
                return_to: return_to,
                user_id: user_id,
                secure: secure,
              )
            Error(Nil) -> invalid_sign_in_redirect(return_to)
          }
        Error(Nil) -> invalid_sign_in_redirect(return_to)
      }
    }
    Error(response) -> response
  }
}

@target(erlang)
pub fn authenticated_user(
  req req: Request(body),
  auth auth: RequestAuth(user),
) -> Result(user, Nil) {
  let cookies = request.get_cookies(req)
  use cookie_value <- result.try(session.find_auth_cookie(cookies))
  use user_id <- result.try(session.decode_user_id(
    encoded: cookie_value,
    session: auth.session,
  ))
  auth.load_user(user_id)
}

@target(erlang)
pub fn authorized_user(
  req req: Request(body),
  auth auth: RequestAuth(user),
) -> Result(user, Nil) {
  use user <- result.try(authenticated_user(req: req, auth: auth))
  case auth.can_access(user) {
    True -> Ok(user)
    False -> Error(Nil)
  }
}

@target(erlang)
pub fn protect(
  req req: Request(body),
  auth auth: RequestAuth(user),
  render render: fn(user) -> response.Response(ResponseData),
) -> response.Response(ResponseData) {
  case authorized_user(req: req, auth: auth) {
    Ok(user) -> render(user)
    Error(Nil) -> sign_in_redirect(req.path)
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
pub fn code_sent_redirect(
  return_to: String,
) -> response.Response(ResponseData) {
  redirect("/sign_in?return_to=" <> uri.percent_encode(return_to) <> "&sent=1")
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
