@target(erlang)
import gleam/http/request.{type Request}
@target(erlang)
import gleam/http/response.{type Response}
@target(erlang)
import gleam/int
@target(erlang)
import gleam/result
@target(erlang)
import gleam/string
@target(erlang)
import mist.{type Connection, type ResponseData}
@target(erlang)
import rally/runtime/db
@target(erlang)
import rally/runtime/env
@target(erlang)
import rally/runtime/http_server
@target(erlang)
import rally/runtime/session
@target(erlang)
import rally/runtime/static
@target(erlang)
import simplifile
@target(erlang)
import sqlight
@target(erlang)
import tom

@target(erlang)
pub type Context {
  Context(db: sqlight.Connection, session: session.AuthSession)
}

@target(erlang)
pub type Config {
  Config(
    package_name: String,
    port: Int,
    database_path: String,
    auth_secret_env: String,
    allow_missing_development_auth_secret: Bool,
    static_prefix: String,
    static_root: String,
    http: http_server.Config,
  )
}

@target(erlang)
pub type Handlers {
  Handlers(
    auth: fn(Request(Connection), Context) ->
      Result(Response(ResponseData), Nil),
    websocket: fn(Request(Connection), Context) -> Response(ResponseData),
    admin: fn(Request(Connection), Context) -> Response(ResponseData),
    public: fn(Request(Connection), Context) -> Response(ResponseData),
  )
}

@target(erlang)
pub type ConfigError {
  CannotReadGleamToml(message: String)
  InvalidGleamToml(message: String)
  InvalidPort(value: String)
}

@target(erlang)
pub type StartError {
  ConfigError(error: ConfigError)
  DatabaseOpenFailed(path: String, message: String)
  AuthSessionConfigFailed(error: session.AuthSessionConfigError)
}

@target(javascript)
pub fn ensure() -> Nil {
  Nil
}

@target(erlang)
pub fn config_from_project(
  default_port default_port: Int,
) -> Result(Config, ConfigError) {
  use toml <- result.try(
    simplifile.read("gleam.toml")
    |> result.map_error(fn(e) {
      CannotReadGleamToml(simplifile.describe_error(e))
    }),
  )

  config_from_toml(
    toml: toml,
    default_port: default_port,
    port_override: env.get("PORT"),
    database_path_override: env.get("DATABASE_PATH"),
  )
}

@target(erlang)
pub fn config_from_toml(
  toml toml: String,
  default_port default_port: Int,
  port_override port_override: Result(String, Nil),
  database_path_override database_path_override: Result(String, Nil),
) -> Result(Config, ConfigError) {
  use toml_map <- result.try(
    tom.parse(toml)
    |> result.map_error(fn(e) { InvalidGleamToml(string.inspect(e)) }),
  )

  use port <- result.try(port_from_env(
    value: port_override,
    default: default_port,
  ))

  let package_name =
    tom.get_string(toml_map, ["name"])
    |> result.unwrap("app")

  let database_path = case database_path_override {
    Ok(path) -> path
    Error(Nil) ->
      tom.get_string(toml_map, ["tools", "marmot", "database"])
      |> result.unwrap("app.db")
  }

  Ok(Config(
    package_name: package_name,
    port: port,
    database_path: database_path,
    auth_secret_env: "SECRET_KEY_BASE",
    allow_missing_development_auth_secret: True,
    static_prefix: "/assets/",
    static_root: "priv/static",
    http: http_server.default_config(),
  ))
}

@target(erlang)
pub fn listen(
  config config: Config,
  handlers handlers: Handlers,
) -> Result(Nil, StartError) {
  use conn <- result.try(
    db.open(config.database_path)
    |> result.map_error(fn(e) {
      DatabaseOpenFailed(path: config.database_path, message: e.message)
    }),
  )
  use auth_session <- result.try(
    session.auth_session_from_env(
      env_var: config.auth_secret_env,
      allow_missing_development_key: config.allow_missing_development_auth_secret,
    )
    |> result.map_error(AuthSessionConfigFailed),
  )

  let context = Context(db: conn, session: auth_session)

  http_server.listen(
    port: config.port,
    context: context,
    config: config.http,
    handlers: http_server.Handlers(
      auth: handlers.auth,
      websocket: handlers.websocket,
      admin: handlers.admin,
      public: fn(req, context) {
        handle_public(req: req, context: context, config: config, handlers:)
      },
    ),
  )
  Ok(Nil)
}

@target(erlang)
pub fn start(
  default_port default_port: Int,
  handlers handlers: Handlers,
) -> Result(Nil, StartError) {
  use config <- result.try(
    config_from_project(default_port:)
    |> result.map_error(ConfigError),
  )
  listen(config:, handlers:)
}

@target(erlang)
pub fn start_error_message(error: StartError) -> String {
  case error {
    ConfigError(error) -> config_error_message(error)
    DatabaseOpenFailed(path, message) ->
      "Cannot open database " <> path <> ": " <> message
    AuthSessionConfigFailed(error) ->
      session.auth_session_config_error_message(error)
  }
}

@target(erlang)
pub fn config_error_message(error: ConfigError) -> String {
  case error {
    CannotReadGleamToml(message) -> "Cannot read gleam.toml: " <> message
    InvalidGleamToml(message) -> "Invalid gleam.toml: " <> message
    InvalidPort(value) ->
      "Invalid PORT value: "
      <> value
      <> ". Set PORT to an integer, for example PORT=8080."
  }
}

@target(erlang)
fn handle_public(
  req req: Request(Connection),
  context context: Context,
  config config: Config,
  handlers handlers: Handlers,
) -> Response(ResponseData) {
  case string.starts_with(req.path, config.static_prefix) {
    True ->
      static.serve_asset(
        root: config.static_root,
        path: string.drop_start(req.path, string.length(config.static_prefix)),
      )
    False -> handlers.public(req, context)
  }
}

@target(erlang)
fn port_from_env(
  value value: Result(String, Nil),
  default default: Int,
) -> Result(Int, ConfigError) {
  case value {
    Ok(raw) ->
      case int.parse(raw) {
        Ok(port) -> Ok(port)
        Error(Nil) -> Error(InvalidPort(raw))
      }
    Error(Nil) -> Ok(default)
  }
}
