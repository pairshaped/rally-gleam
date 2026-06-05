@target(erlang)
import gleam/bytes_tree
@target(erlang)
import gleam/http/request.{type Request}
@target(erlang)
import gleam/http/response.{type Response}
@target(erlang)
import gleam/int
@target(erlang)
import gleam/list
@target(erlang)
import gleam/string
@target(erlang)
import mist.{type ResponseData}

@target(erlang)
pub type BootAttribute {
  StringAttribute(name: String, value: String)
  IntAttribute(name: String, value: Int)
  BoolAttribute(name: String, value: Bool)
}

@target(erlang)
pub type Mount {
  Admin
  Public
}

@target(javascript)
pub fn ensure() -> Nil {
  Nil
}

@target(erlang)
pub fn html_response(body: String) -> Response(ResponseData) {
  response.new(200)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

@target(erlang)
pub fn query_params(
  req req: Request(body),
  from_values from_values: fn(List(#(String, String))) -> params,
  empty empty: fn() -> params,
) -> params {
  case request.get_query(req) {
    Ok(values) -> from_values(values)
    Error(Nil) -> empty()
  }
}

@target(erlang)
pub fn standard_mount(
  path path: String,
  admin_prefix admin_prefix: String,
) -> Mount {
  case string.starts_with(path, admin_prefix) {
    True -> Admin
    False -> Public
  }
}

@target(erlang)
pub fn standard_entrypoint(mount: Mount) -> String {
  case mount {
    Admin -> "admin_app.mjs"
    Public -> "public_app.mjs"
  }
}

@target(erlang)
pub fn hydration_attr(payloads: List(String)) -> String {
  case payloads {
    [] -> ""
    _ ->
      " data-hydration=\""
      <> html_attr_escape(string.join(payloads, ","))
      <> "\""
  }
}

@target(erlang)
pub fn boot_attrs(attrs: List(BootAttribute)) -> String {
  attrs
  |> list.map(boot_attr)
  |> string.join("")
}

@target(erlang)
fn boot_attr(attr: BootAttribute) -> String {
  case attr {
    StringAttribute(name, value) ->
      " data-" <> name <> "=\"" <> html_attr_escape(value) <> "\""
    IntAttribute(name, value) ->
      " data-" <> name <> "=\"" <> int.to_string(value) <> "\""
    BoolAttribute(name, value) ->
      " data-" <> name <> "=\"" <> bool_attr(value) <> "\""
  }
}

// nolint: prefer_guard_clause -- this is a string conversion helper.
@target(erlang)
fn bool_attr(value: Bool) -> String {
  case value {
    True -> "1"
    False -> "0"
  }
}

@target(erlang)
fn html_attr_escape(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("\"", "&quot;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}
