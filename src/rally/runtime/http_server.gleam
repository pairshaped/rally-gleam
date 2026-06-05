@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/http/request.{type Request, Request}
@target(erlang)
import gleam/http/response.{type Response}
@target(erlang)
import gleam/int
@target(erlang)
import gleam/io
@target(erlang)
import gleam/string
@target(erlang)
import mist.{type Connection, type ResponseData}
@target(erlang)
import rally/runtime/static

@target(erlang)
pub type Config {
  Config(websocket_path: String, asset_prefix: String, admin_prefix: String)
}

@target(erlang)
pub type Handlers(context) {
  Handlers(
    auth: fn(Request(Connection), context) ->
      Result(Response(ResponseData), Nil),
    websocket: fn(Request(Connection), context) -> Response(ResponseData),
    admin: fn(Request(Connection), context) -> Response(ResponseData),
    public: fn(Request(Connection), context) -> Response(ResponseData),
  )
}

@target(erlang)
pub fn default_config() -> Config {
  Config(
    websocket_path: "/ws",
    asset_prefix: "/_build/",
    admin_prefix: "/admin",
  )
}

@target(erlang)
pub fn listen(
  port port: Int,
  context context: context,
  config config: Config,
  handlers handlers: Handlers(context),
) -> Nil {
  io.println("Listening on http://localhost:" <> int.to_string(port))
  let assert Ok(_) =
    mist.new(fn(req) { handle(req: req, context: context, config:, handlers:) })
    |> mist.port(port)
    |> mist.start
  process.sleep_forever()
}

@target(erlang)
pub fn handle(
  req req: Request(Connection),
  context context: context,
  config config: Config,
  handlers handlers: Handlers(context),
) -> Response(ResponseData) {
  case handlers.auth(req, context) {
    Ok(response) -> response
    Error(Nil) -> handle_framework_route(req: req, context:, config:, handlers:)
  }
}

@target(erlang)
fn handle_framework_route(
  req req: Request(Connection),
  context context: context,
  config config: Config,
  handlers handlers: Handlers(context),
) -> Response(ResponseData) {
  let Request(path: path, ..) = req
  case path == config.websocket_path {
    True -> handlers.websocket(req, context)
    False ->
      case string.starts_with(path, config.asset_prefix) {
        True ->
          static.serve_javascript_build(string.drop_start(
            path,
            string.length(config.asset_prefix),
          ))
        False ->
          case string.starts_with(path, config.admin_prefix) {
            True -> handlers.admin(req, context)
            False -> handlers.public(req, context)
          }
      }
  }
}

@target(javascript)
pub fn ensure() -> Nil {
  Nil
}
