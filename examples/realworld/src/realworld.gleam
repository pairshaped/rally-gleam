import envoy
import generated/public/http_handler
import generated/public/router
import generated/public/ssr_handler
import generated/public/ws_handler
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{Get, Post}
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
import server_context.{ServerContext}
import simplifile
import sqlight

const client_build_root = ".generated_clients/public/build/dev/javascript"

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
  ensure_db_dir()
  let db = start_db()
  system.start("db/system.db")
  let server_context = ServerContext(db:)
  let port = server_port()

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
          Post -> {
            let session_id = session_id(req)
            case mist.read_body(req, max_body_limit: 16_000_000) {
              Ok(Request(body: body, ..)) -> {
                let resp =
                  http_handler.handle(
                    body: body,
                    server_context: server_context,
                    session_id: session_id,
                  )
                case request.get_header(req, "cookie") {
                  Ok(cookie) ->
                    case session.extract_session_id(cookie) {
                      Ok(_) -> resp
                      Error(_error) ->
                        response.set_header(
                          resp,
                          "set-cookie",
                          session.set_cookie_header(
                            session_id:,
                            secure: env.secure_cookies(),
                          ),
                        )
                    }
                  Error(_error) ->
                    response.set_header(
                      resp,
                      "set-cookie",
                      session.set_cookie_header(
                        session_id:,
                        secure: env.secure_cookies(),
                      ),
                    )
                }
              }
              Error(_error) ->
                response.new(413)
                |> response.set_body(
                  mist.Bytes(bytes_tree.from_string("Request body too large")),
                )
            }
          }
          _ ->
            response.new(405)
            |> response.set_body(
              mist.Bytes(bytes_tree.from_string("Not found")),
            )
        }
      }
      _ -> {
        case string.starts_with(path, "/_build/") {
          True -> serve_static(string.drop_start(path, 8))
          False ->
            case method {
              Get -> {
                let session_id = session_id(req)
                let route = router.parse_route(request.to_uri(req))
                let hostname =
                  request.get_header(req, "host") |> result.unwrap("")
                let resp =
                  ssr_handler.handle_request(
                    route: route,
                    server_context: server_context,
                    session_id: session_id,
                    hostname: hostname,
                  )
                case request.get_header(req, "cookie") {
                  Ok(cookie) ->
                    case session.extract_session_id(cookie) {
                      Ok(_) -> resp
                      Error(_error) ->
                        response.set_header(
                          resp,
                          "set-cookie",
                          session.set_cookie_header(
                            session_id:,
                            secure: env.secure_cookies(),
                          ),
                        )
                    }
                  Error(_error) ->
                    response.set_header(
                      resp,
                      "set-cookie",
                      session.set_cookie_header(
                        session_id:,
                        secure: env.secure_cookies(),
                      ),
                    )
                }
              }
              _ ->
                response.new(405)
                |> response.set_body(
                  mist.Bytes(bytes_tree.from_string("Not found")),
                )
            }
        }
      }
    }
  }

  io.println("Listening on http://localhost:" <> int.to_string(port))
  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(port)
    |> mist.start
  process.sleep_forever()
}

fn load_dotenv() -> Nil {
  case simplifile.read(".env") {
    Ok(contents) ->
      contents
      |> string.split("\n")
      |> list.each(load_dotenv_line)
    Error(_) -> Nil
  }
}

fn load_dotenv_line(raw_line: String) -> Nil {
  let line = string.trim(raw_line)
  case line == "" || string.starts_with(line, "#") {
    True -> Nil
    False -> {
      let line = case string.starts_with(line, "export ") {
        True -> string.drop_start(line, 7)
        False -> line
      }
      case string.split_once(line, "=") {
        Ok(#(name, value)) -> set_env_if_missing(string.trim(name), value)
        Error(_) -> Nil
      }
    }
  }
}

fn set_env_if_missing(name: String, value: String) -> Nil {
  case name == "" {
    True -> Nil
    False ->
      case envoy.get(name) {
        Ok(_) -> Nil
        Error(_) -> envoy.set(name, clean_env_value(value))
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

fn server_port() -> Int {
  let raw = envoy.get("PORT") |> result.unwrap("8080")
  case int.parse(raw) {
    Ok(port) -> port
    Error(_) ->
      panic as {
        "Invalid PORT value: "
        <> raw
        <> ". Set PORT to an integer, for example PORT=8080."
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
          let content_type = case string.ends_with(path, ".mjs") {
            True -> "application/javascript"
            False ->
              case string.ends_with(path, ".js") {
                True -> "application/javascript"
                False -> "application/octet-stream"
              }
          }
          response.new(200)
          |> response.set_header("content-type", content_type)
          |> response.set_body(mist.Bytes(bytes_tree.from_string(content)))
        }
        Error(_error) ->
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
      }
  }
}

fn start_db() -> sqlight.Connection {
  let assert Ok(conn) = db.open("db/realworld.db")
  conn
}

fn ensure_db_dir() -> Nil {
  let assert Ok(Nil) = simplifile.create_directory_all("db")
  Nil
}
