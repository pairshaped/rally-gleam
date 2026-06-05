@target(erlang)
import gleam/bytes_tree
@target(erlang)
import gleam/http/response.{type Response}
@target(erlang)
import gleam/io
@target(erlang)
import gleam/option.{None}
@target(erlang)
import gleam/string
@target(erlang)
import mist.{type ResponseData}

@target(erlang)
pub fn serve_javascript_build(path: String) -> Response(ResponseData) {
  serve_asset(root: "build/dev/javascript", path:)
}

@target(erlang)
pub fn serve_asset(
  root root: String,
  path path: String,
) -> Response(ResponseData) {
  case valid_asset_path(path) {
    False -> not_found(path)
    True ->
      case mist.send_file(root <> "/" <> path, offset: 0, limit: None) {
        Ok(data) ->
          response.new(200)
          |> response.set_header("content-type", content_type(path))
          |> response.set_body(data)
        Error(reason) -> {
          io.println(
            "Static file not found: "
            <> path
            <> " ("
            <> string.inspect(reason)
            <> ")",
          )
          not_found(path)
        }
      }
  }
}

@target(erlang)
fn content_type(path: String) -> String {
  case string.ends_with(path, ".mjs") || string.ends_with(path, ".js") {
    True -> "application/javascript; charset=utf-8"
    False ->
      case string.ends_with(path, ".css") {
        True -> "text/css; charset=utf-8"
        False -> "application/octet-stream"
      }
  }
}

@target(erlang)
fn valid_asset_path(path: String) -> Bool {
  !string.starts_with(path, "/")
  && !string.contains(path, "../")
  && path != ".."
}

@target(erlang)
fn not_found(_path: String) -> Response(ResponseData) {
  response.new(404)
  |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
}

@target(javascript)
pub fn ensure() -> Nil {
  Nil
}
