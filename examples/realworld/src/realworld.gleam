import envoy
import generated/public/http_handler
import generated/public/router
import generated/public/ssr_handler
import generated/public/ws_handler
import gleam/bool
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{type Method, Get, Post}
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
import rally/runtime/db
import rally/runtime/env

import rally/runtime/session
import rally/runtime/system
import server_context.{type ServerContext, ServerContext}
import simplifile
import sqlight

const client_build_root = ".generated_clients/public/build/dev/javascript"

type AppError {
  AppError(message: String)
}

fn session_id(req: Request(Connection)) -> String {
  request.get_header(req, "cookie")
  |> result.map(fn(cookie) {
    result.lazy_unwrap(session.extract_session_id(cookie), or: fn() {
      session.generate_id()
    })
  })
  |> result.lazy_unwrap(or: fn() { session.generate_id() })
}

pub fn main() -> Nil {
  load_dotenv()
  case start_app() {
    Ok(Nil) -> process.sleep_forever()
    Error(error) -> io.println(app_error_message(error:))
  }
}

fn start_app() -> Result(Nil, AppError) {
  use Nil <- result.try(ensure_db_dir())
  use db <- result.try(start_db())
  system.start("db/system.db")
  let server_context = ServerContext(db:)
  use port <- result.try(server_port())

  let handler = fn(req: Request(Connection)) -> Response(ResponseData) {
    let Request(path: path, method: method, ..) = req
    case path {
      "/ws" -> {
        let session_id = session_id(req)
        let hostname =
          request.get_header(req, "host")
          |> result.unwrap("")
        mist.websocket(
          req,
          ws_handler.handler,
          fn(conn) {
            ws_handler.on_init(
              conn: conn,
              server_context: server_context,
              session_id: session_id,
              hostname: hostname,
            )
          },
          ws_handler.on_close,
        )
      }
      "/rpc" -> {
        case method {
          Post -> handle_rpc(req: req, server_context:)
          _ ->
            response.new(405)
            |> response.set_body(
              mist.Bytes(bytes_tree.from_string("Not found")),
            )
        }
      }
      _ ->
        handle_page_or_static(
          path: path,
          method: method,
          req: req,
          server_context: server_context,
        )
    }
  }

  io.println("Listening on http://localhost:" <> int.to_string(port))
  mist.new(handler)
  |> mist.port(port)
  |> mist.start
  |> result.map(fn(started) {
    let _server = started
    Nil
  })
  |> result.map_error(fn(error) {
    let _start_error = error
    AppError("Failed to start server")
  })
}

fn handle_page_or_static(
  path path: String,
  method method: Method,
  req req: Request(Connection),
  server_context server_context: ServerContext,
) -> Response(ResponseData) {
  case string.starts_with(path, "/_build/") {
    True -> serve_static(string.drop_start(path, 8))
    False ->
      case method {
        Get -> handle_ssr(req: req, server_context:)
        _ ->
          response.new(405)
          |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
      }
  }
}

fn handle_rpc(
  req req: Request(Connection),
  server_context server_context: ServerContext,
) -> Response(ResponseData) {
  let session_id = session_id(req)
  case mist.read_body(req, max_body_limit: 16_000_000) {
    Ok(Request(body: body, ..)) -> {
      let resp =
        http_handler.handle(
          body: body,
          server_context: server_context,
          session_id: session_id,
        )
      set_session_cookie_if_missing(resp: resp, req: req, session_id:)
    }
    Error(error) -> request_body_too_large(error:)
  }
}

fn handle_ssr(
  req req: Request(Connection),
  server_context server_context: ServerContext,
) -> Response(ResponseData) {
  let session_id = session_id(req)
  let route = router.parse_route(request.to_uri(req))
  let hostname = request.get_header(req, "host") |> result.unwrap("")
  let resp =
    ssr_handler.handle_request(
      route: route,
      server_context: server_context,
      session_id: session_id,
      hostname: hostname,
    )
  set_session_cookie_if_missing(resp: resp, req: req, session_id:)
}

fn set_session_cookie_if_missing(
  resp resp: Response(ResponseData),
  req req: Request(Connection),
  session_id session_id: String,
) -> Response(ResponseData) {
  case request.get_header(req, "cookie") {
    Ok(cookie) ->
      case session.extract_session_id(cookie) {
        Ok(_) -> resp
        Error(error) -> {
          let _missing_session_id = error
          set_session_cookie(resp: resp, session_id:)
        }
      }
    Error(error) -> {
      let _missing_cookie = error
      set_session_cookie(resp: resp, session_id:)
    }
  }
}

fn set_session_cookie(
  resp resp: Response(ResponseData),
  session_id session_id: String,
) -> Response(ResponseData) {
  response.set_header(
    resp,
    "set-cookie",
    session.set_cookie_header(session_id:, secure: env.secure_cookies()),
  )
}

fn request_body_too_large(error error: a) -> Response(ResponseData) {
  let _read_error = error
  response.new(413)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("Request body too large")),
  )
}

fn load_dotenv() -> Nil {
  case simplifile.read(".env") {
    Ok(contents) ->
      contents
      |> string.split("\n")
      |> list.each(load_dotenv_line)
    Error(error) -> {
      let _missing_dotenv = error
      Nil
    }
  }
}

fn load_dotenv_line(raw_line: String) -> Nil {
  let line = string.trim(raw_line)
  use <- bool.guard(
    when: line == "" || string.starts_with(line, "#"),
    return: Nil,
  )
  let line = case string.starts_with(line, "export ") {
    True -> string.drop_start(line, 7)
    False -> line
  }
  case string.split_once(line, "=") {
    Ok(#(name, value)) -> set_env_if_missing(string.trim(name), value)
    Error(error) -> {
      let _invalid_env_line = error
      Nil
    }
  }
}

fn set_env_if_missing(name: String, value: String) -> Nil {
  use <- bool.guard(when: name == "", return: Nil)
  case envoy.get(name) {
    Ok(_) -> Nil
    Error(error) -> {
      let _missing_env = error
      envoy.set(name, clean_env_value(value))
    }
  }
}

fn clean_env_value(value: String) -> String {
  let value = string.trim(value)
  case string.starts_with(value, "\"") && string.ends_with(value, "\"") {
    True -> value |> string.drop_start(1) |> string.drop_end(1)
    False ->
      case string.starts_with(value, "'") && string.ends_with(value, "'") {
        True -> value |> string.drop_start(1) |> string.drop_end(1)
        False -> value
      }
  }
}

fn server_port() -> Result(Int, AppError) {
  let raw = envoy.get("PORT") |> result.unwrap("8080")
  case int.parse(raw) {
    Ok(port) -> Ok(port)
    Error(error) -> {
      let _parse_error = error
      Error(AppError(
        "Invalid PORT value: "
        <> raw
        <> ". Set PORT to an integer, for example PORT=8080.",
      ))
    }
  }
}

fn serve_static(path: String) -> Response(ResponseData) {
  let file_path = client_build_root <> "/" <> path
  let has_traversal =
    string.split(path, "/")
    |> list.any(fn(seg) { seg == ".." || seg == "." })
  case has_traversal {
    True ->
      response.new(403)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Forbidden")))
    False ->
      case simplifile.read(file_path) {
        Ok(content) -> {
          let content_type = static_content_type(path: path)
          response.new(200)
          |> response.set_header("content-type", content_type)
          |> response.set_body(mist.Bytes(bytes_tree.from_string(content)))
        }
        Error(error) -> {
          let _missing_file = error
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
        }
      }
  }
}

fn static_content_type(path path: String) -> String {
  use <- bool.guard(
    when: string.ends_with(path, ".mjs") || string.ends_with(path, ".js"),
    return: "application/javascript",
  )
  "application/octet-stream"
}

fn start_db() -> Result(sqlight.Connection, AppError) {
  case db.open("db/realworld.db") {
    Ok(conn) -> Ok(conn)
    Error(error) -> {
      let _db_error = error
      Error(AppError("Failed to open db/realworld.db"))
    }
  }
}

fn ensure_db_dir() -> Result(Nil, AppError) {
  case simplifile.create_directory_all("db") {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> {
      let _dir_error = error
      Error(AppError("Failed to create db directory"))
    }
  }
}

fn app_error_message(error error: AppError) -> String {
  let AppError(message) = error
  message
}
