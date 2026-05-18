import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type ScaffoldFile {
  ScaffoldFile(path: String, contents: String)
}

pub fn init_project(root: String) -> Result(Nil, String) {
  let name = project_name(root)
  let scaffold_files = files(name)

  use Nil <- result.try(ensure_safe_to_write(root, name, scaffold_files))
  use Nil <- result.try(create_dirs(root))
  use Nil <- result.try(write_files(root, scaffold_files))
  write_readme_if_missing(root, name)
  Ok(Nil)
}

pub fn files(project_name: String) -> List(ScaffoldFile) {
  [
    ScaffoldFile(".gitignore", gitignore()),
    ScaffoldFile(".env", env_example()),
    ScaffoldFile(".env.example", env_example()),
    ScaffoldFile("gleam.toml", gleam_toml(project_name)),
    ScaffoldFile("migrations/001_create_counter.sql", migration_001()),
    ScaffoldFile("src/sql/counter/get.sql", counter_get_sql()),
    ScaffoldFile("src/sql/counter/increment.sql", counter_increment_sql()),
    ScaffoldFile("src/sql/counter/decrement.sql", counter_decrement_sql()),
    ScaffoldFile("src/public/pages/home_.gleam", home_page()),
    ScaffoldFile("src/public/pages/layout.gleam", layout_page()),
    ScaffoldFile("src/" <> project_name <> ".gleam", app_module(project_name)),
    ScaffoldFile("src/public/shell.html", shell_html()),
    ScaffoldFile("src/server_context.gleam", server_context()),
  ]
}

fn create_dirs(root: String) -> Result(Nil, String) {
  [
    "migrations",
    "db",
    "src/public/pages",
    "src/sql/counter",
    "src/generated/public",
    ".generated_clients/public/src/generated",
  ]
  |> list.try_each(fn(dir) {
    let path = join(root, dir)
    simplifile.create_directory_all(path)
    |> result.map_error(fn(e) {
      "Failed to create " <> path <> ": " <> simplifile.describe_error(e)
    })
  })
}

fn write_files(root: String, files: List(ScaffoldFile)) -> Result(Nil, String) {
  files
  |> list.try_each(fn(file) {
    let path = join(root, file.path)
    simplifile.write(to: path, contents: file.contents)
    |> result.map_error(fn(e) {
      "Failed to write " <> path <> ": " <> simplifile.describe_error(e)
    })
  })
}

fn ensure_safe_to_write(
  root: String,
  project_name: String,
  files: List(ScaffoldFile),
) -> Result(Nil, String) {
  files
  |> list.try_each(fn(file) {
    let path = join(root, file.path)
    case simplifile.is_file(path) {
      Ok(True) -> ensure_file_safe_to_overwrite(path, file, project_name)
      Ok(False) -> ensure_path_is_missing(path, file.path)
      Error(e) ->
        Error(
          "Failed to inspect "
          <> file.path
          <> ": "
          <> simplifile.describe_error(e),
        )
    }
  })
}

fn ensure_file_safe_to_overwrite(
  path: String,
  file: ScaffoldFile,
  project_name: String,
) -> Result(Nil, String) {
  case simplifile.read(path) {
    Ok(existing) -> {
      case can_overwrite(file, project_name, existing) {
        True -> Ok(Nil)
        False -> Error(refuse_overwrite_message(file.path))
      }
    }
    Error(e) ->
      Error(
        "Failed to read existing "
        <> file.path
        <> ": "
        <> simplifile.describe_error(e),
      )
  }
}

fn ensure_path_is_missing(
  path: String,
  relative_path: String,
) -> Result(Nil, String) {
  case simplifile.is_directory(path) {
    Ok(False) -> Ok(Nil)
    Ok(True) ->
      Error(
        "Refusing to overwrite "
        <> relative_path
        <> ". This path already exists as a directory, so Rally stopped before writing anything.",
      )
    Error(e) ->
      Error(
        "Failed to inspect "
        <> relative_path
        <> ": "
        <> simplifile.describe_error(e),
      )
  }
}

fn refuse_overwrite_message(path: String) -> String {
  "Refusing to overwrite "
  <> path
  <> ". This file already exists, so Rally stopped before writing anything. Run `rally init` in a fresh `gleam new` project, or remove this file if you are certain it is disposable."
}

fn can_overwrite(
  file: ScaffoldFile,
  project_name: String,
  existing: String,
) -> Bool {
  let ScaffoldFile(path:, ..) = file
  is_default_gleam_new_file(path, project_name, existing)
}

fn is_default_gleam_new_file(
  path: String,
  project_name: String,
  existing: String,
) -> Bool {
  case path {
    ".gitignore" -> existing == "*.beam
*.ez
/build
erl_crash.dump
"
    "gleam.toml" -> is_default_gleam_toml(existing, project_name)
    _ -> {
      case path == "src/" <> project_name <> ".gleam" {
        True -> existing == "import gleam/io

pub fn main() -> Nil {
  io.println(\"Hello from " <> project_name <> "!\")
}
"
        False -> False
      }
    }
  }
}

fn is_default_gleam_toml(existing: String, project_name: String) -> Bool {
  let header = "name = \"" <> project_name <> "\"
version = \"1.0.0\"

# Fill out these fields if you intend to generate HTML documentation or publish
# your project to the Hex package manager.
#
# description = \"\"
# licences = [\"Apache-2.0\"]
# repository = { type = \"github\", user = \"\", repo = \"\" }
# links = [{ title = \"Website\", href = \"\" }]
#
# For a full reference of all the available options, you can have a look at
# https://gleam.run/writing-gleam/gleam-toml/.

[dependencies]
"

  let footer =
    "
[dev_dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
"

  case
    string.starts_with(existing, header) && string.ends_with(existing, footer)
  {
    False -> False
    True -> {
      existing
      |> string.drop_start(string.length(header))
      |> string.drop_end(string.length(footer))
      |> string.split("\n")
      |> list.map(string.trim)
      |> list.filter(fn(line) { line != "" })
      |> is_default_dependency_lines
    }
  }
}

fn is_default_dependency_lines(lines: List(String)) -> Bool {
  let stdlib = "gleam_stdlib = \">= 1.0.0 and < 2.0.0\""
  lines |> list.contains(stdlib)
  && list.length(lines) <= 3
  && lines
  |> list.all(fn(line) {
    line == stdlib
    || string.starts_with(line, "rally = ")
    || string.starts_with(line, "libero = ")
  })
}

fn project_name(root: String) -> String {
  let path = case root {
    "." -> simplifile.current_directory() |> result.unwrap("rally_app")
    other -> other
  }

  path
  |> trim_trailing_slash
  |> basename
  |> string.replace(each: "-", with: "_")
  |> string.lowercase
}

fn trim_trailing_slash(path: String) -> String {
  use <- bool.guard(when: !string.ends_with(path, "/"), return: path)
  string.drop_end(path, 1) |> trim_trailing_slash
}

fn basename(path: String) -> String {
  path
  |> string.split("/")
  |> list.reverse
  |> list.first
  |> result.unwrap("rally_app")
}

fn write_readme_if_missing(root: String, project_name: String) -> Nil {
  let path = join(root, "README.md")
  case simplifile.is_file(path) {
    Ok(True) -> {
      case simplifile.read(path) {
        Ok(existing) ->
          case existing == default_gleam_new_readme(project_name) {
            True -> {
              let _ = simplifile.write(to: path, contents: readme(project_name))
              Nil
            }
            False -> Nil
          }
        _ -> Nil
      }
    }
    _ -> {
      let _ = simplifile.write(to: path, contents: readme(project_name))
      Nil
    }
  }
}

fn default_gleam_new_readme(project_name: String) -> String {
  "# " <> project_name <> "

[![Package Version](https://img.shields.io/hexpm/v/" <> project_name <> ")](https://hex.pm/packages/" <> project_name <> ")
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/" <> project_name <> "/)

```sh
gleam add " <> project_name <> "@1
```
```gleam
import " <> project_name <> "

pub fn main() -> Nil {
  // TODO: An example of the project in use
}
```

Further documentation can be found at <https://hexdocs.pm/" <> project_name <> ">.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
"
}

fn join(root: String, path: String) -> String {
  case root {
    "." -> path
    _ -> root <> "/" <> path
  }
}

fn gitignore() -> String {
  "build/
.env
db/
erl_crash.dump
*.bak
.DS_Store
.generated_clients/
"
}

fn env_example() -> String {
  "APP_ENV=dev
LOG_LEVEL=debug
PORT=8080
"
}

fn gleam_toml(project_name: String) -> String {
  "name = \"" <> project_name <> "\"
version = \"0.1.0\"
target = \"erlang\"

[dependencies]
envoy = \">= 1.2.0 and < 2.0.0\"
gleam_erlang = \">= 1.0.0 and < 2.0.0\"
gleam_http = \">= 4.0.0 and < 5.0.0\"
gleam_stdlib = \">= 0.60.0 and < 2.0.0\"
rally = \">= 1.0.0 and < 2.0.0\"
libero = \">= 6.0.0 and < 7.0.0\"
lustre = \">= 5.7.0 and < 7.0.0\"
marmot = \">= 1.3.0 and < 2.0.0\"
mist = \">= 6.0.0 and < 7.0.0\"
sqlight = \">= 1.0.0 and < 2.0.0\"
simplifile = \">= 2.0.0 and < 3.0.0\"
gleam_time = \">= 1.7.0 and < 2.0.0\"

[dev-dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
birdie = \">= 2.0.0 and < 3.0.0\"
glinter = \">= 2.16.0 and < 3.0.0\"

[tools.glinter]
stats = true
warnings_as_errors = true
exclude = [\"src/generated/\"]

[[tools.rally.clients]]
namespace = \"public\"
route_root = \"/\"

[tools.marmot]
database = \"db/" <> project_name <> ".db\"
sql_dir = \"src/sql\"
output = \"src/generated/sql\"
"
}

fn home_page() -> String {
  "// Scaffolded by rally: yours to customize.
import generated/sql/counter_sql
import gleam/int
import lustre/element.{type Element}
import lustre/element/html
import lustre/effect.{type Effect}
import lustre/event
import rally_runtime/effect as rally_effect
import server_context.{type ServerContext}

pub type Model {
  Model(count: Int)
}

pub type Msg {
  UserClickedIncrement
  UserClickedDecrement
  GotCount(Result(Int, Nil))
}

pub type ServerIncrement {
  ServerIncrement
}

pub type ServerDecrement {
  ServerDecrement
}

pub fn load(server_context: ServerContext) -> Model {
  let assert Ok([row]) = counter_sql.get(db: server_context.db)
  Model(count: row.value)
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(count: 0), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserClickedIncrement ->
      #(model, rally_effect.rpc(ServerIncrement, on_response: GotCount))
    UserClickedDecrement ->
      #(model, rally_effect.rpc(ServerDecrement, on_response: GotCount))
    GotCount(Ok(count)) -> #(Model(count:), effect.none())
    GotCount(Error(_)) -> #(model, effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.button([event.on_click(UserClickedIncrement)], [html.text(\"+\")]),
    html.text(int.to_string(model.count)),
    html.button([event.on_click(UserClickedDecrement)], [html.text(\"-\")]),
  ])
}

pub fn server_increment(
  msg _msg: ServerIncrement,
  server_context server_context: ServerContext,
) -> Result(Int, Nil) {
  case counter_sql.increment(db: server_context.db) {
    Ok([row]) -> Ok(row.value)
    _ -> Error(Nil)
  }
}

pub fn server_decrement(
  msg _msg: ServerDecrement,
  server_context server_context: ServerContext,
) -> Result(Int, Nil) {
  case counter_sql.decrement(db: server_context.db) {
    Ok([row]) -> Ok(row.value)
    _ -> Error(Nil)
  }
}
"
}

fn layout_page() -> String {
  "// Scaffolded by rally: yours to customize.
import lustre/element.{type Element}

pub fn layout(content: Element(msg)) -> Element(msg) {
  content
}
"
}

fn app_module(project_name: String) -> String {
  "// Scaffolded by rally: yours to customize.
import envoy
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request.{type Request, Request}
import gleam/http/response
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import mist.{type Connection}
import generated/public/http_handler as http_handler
import generated/public/router as router
import generated/public/ssr_handler as ssr_handler
import generated/public/ws_handler as ws_handler
import rally_runtime/db
import rally_runtime/env
import rally_runtime/session
import rally_runtime/system
import server_context.{type ServerContext, ServerContext}
import simplifile
import sqlight

const db_dir = \"db\"

const db_path = \"db/" <> project_name <> ".db\"

const client_build_root = \".generated_clients/public/build/dev/javascript\"

pub fn main() {
  load_dotenv()
  ensure_db_dir()
  let db = start_db()
  system.start(\"db/system.db\")
  let server_context = ServerContext(db:)
  let port = server_port()

  let handler = fn(req: Request(Connection)) {
    let Request(path: path, method: method, ..) = req
    case path {
      \"/ws\" -> {
        let session_id = get_session_id(req)
        let hostname = request_header(req, \"host\")
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
      \"/rpc\" -> handle_rpc(req, server_context)
      _ -> {
        case string.starts_with(path, \"/_build/\") {
          True -> serve_static(string.drop_start(path, 8))
          False ->
            case method {
              Get -> {
                let session_id = get_session_id(req)
                let hostname = request_header(req, \"host\")
                let route = router.parse_route(request.to_uri(req))
                let resp =
                  ssr_handler.handle_request(
                    route: route,
                    server_context: server_context,
                    session_id: session_id,
                    hostname: hostname,
                  )
                set_session_cookie_if_missing(req, resp, session_id)
              }
              _ ->
                response.new(405)
                |> response.set_body(mist.Bytes(bytes_tree.from_string(\"Not found\")))
            }
        }
      }
    }
  }

  io.println(\"Listening on http://localhost:\" <> int.to_string(port))
  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(port)
    |> mist.start
  process.sleep_forever()
}

fn load_dotenv() -> Nil {
  case simplifile.read(\".env\") {
    Ok(contents) ->
      contents
      |> string.split(\"\\n\")
      |> list.each(load_dotenv_line)
    Error(_) -> Nil
  }
}

fn load_dotenv_line(raw_line: String) -> Nil {
  let line = string.trim(raw_line)
  case line == \"\" || string.starts_with(line, \"#\") {
    True -> Nil
    False -> {
      let line = case string.starts_with(line, \"export \") {
        True -> string.drop_start(line, 7)
        False -> line
      }
      case string.split_once(line, \"=\") {
        Ok(#(name, value)) -> set_env_if_missing(string.trim(name), value)
        Error(_) -> Nil
      }
    }
  }
}

fn set_env_if_missing(name: String, value: String) -> Nil {
  case name == \"\" {
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
  case string.starts_with(value, \"\\\"\") && string.ends_with(value, \"\\\"\") {
    True -> value |> string.drop_start(1) |> string.drop_end(1)
    False ->
      case string.starts_with(value, \"'\") && string.ends_with(value, \"'\") {
        True -> value |> string.drop_start(1) |> string.drop_end(1)
        False -> value
      }
  }
}

fn ensure_db_dir() -> Nil {
  let assert Ok(Nil) = simplifile.create_directory_all(db_dir)
  Nil
}

fn server_port() -> Int {
  let raw = envoy.get(\"PORT\") |> result.unwrap(\"8080\")
  case int.parse(raw) {
    Ok(port) -> port
    Error(_) ->
      panic as {
        \"Invalid PORT value: \"
        <> raw
        <> \". Set PORT to an integer, for example PORT=8080.\"
      }
  }
}

fn handle_rpc(req: Request(Connection), server_context: ServerContext) {
  case req.method {
    Post -> {
      let session_id = get_session_id(req)
      case mist.read_body(req, max_body_limit: 16_000_000) {
        Ok(Request(body: body, ..)) -> {
          let resp =
            http_handler.handle(
              body: body,
              server_context: server_context,
              session_id: session_id,
            )
          set_session_cookie_if_missing(req, resp, session_id)
        }
        Error(_) ->
          response.new(413)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string(\"Request body too large\")),
          )
      }
    }
    _ ->
      response.new(405)
      |> response.set_body(mist.Bytes(bytes_tree.from_string(\"Not found\")))
  }
}

fn request_header(req: Request(Connection), name: String) -> String {
  case request.get_header(req, name) {
    Ok(value) -> value
    Error(_) -> \"\"
  }
}

fn get_session_id(req: Request(Connection)) -> String {
  case request.get_header(req, \"cookie\") {
    Ok(cookie) ->
      case session.extract_session_id(cookie) {
        Ok(id) -> id
        Error(_) -> session.generate_id()
      }
    Error(_) -> session.generate_id()
  }
}

fn set_session_cookie_if_missing(req, resp, session_id: String) {
  case request.get_header(req, \"cookie\") {
    Ok(cookie) ->
      case session.extract_session_id(cookie) {
        Ok(_) -> resp
        Error(_) ->
          response.set_header(
            resp,
            \"set-cookie\",
            session.set_cookie_header(session_id:, secure: env.secure_cookies()),
          )
      }
    Error(_) ->
      response.set_header(
        resp,
        \"set-cookie\",
        session.set_cookie_header(session_id:, secure: env.secure_cookies()),
      )
  }
}

fn serve_static(path: String) {
  let has_traversal =
    path
    |> string.split(\"/\")
    |> list.any(fn(seg) { seg == \"..\" || seg == \".\" })

  case has_traversal {
    True ->
      response.new(403)
      |> response.set_body(mist.Bytes(bytes_tree.from_string(\"Forbidden\")))
    False -> {
      let file_path = client_build_root <> \"/\" <> path
      case simplifile.read(file_path) {
        Ok(content) ->
          response.new(200)
          |> response.set_header(\"content-type\", content_type(path))
          |> response.set_body(mist.Bytes(bytes_tree.from_string(content)))
        Error(_) ->
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.from_string(\"Not found\")))
      }
    }
  }
}

fn content_type(path: String) -> String {
  case string.ends_with(path, \".mjs\") || string.ends_with(path, \".js\") {
    True -> \"application/javascript\"
    False -> \"application/octet-stream\"
  }
}

fn start_db() -> sqlight.Connection {
  let assert Ok(conn) = db.open(db_path)
  conn
}
"
}

fn shell_html() -> String {
  "<!-- Scaffolded by rally: yours to customize. -->
<!DOCTYPE html>
<html>
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>My App</title>
</head>
<body>
  <div id=\"app\"></div>
  {{rally_client_script}}
</body>
</html>
"
}

fn migration_001() -> String {
  "CREATE TABLE counter (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  value INTEGER NOT NULL
);

INSERT INTO counter (id, value) VALUES (1, 0);
"
}

fn counter_get_sql() -> String {
  "SELECT value FROM counter WHERE id = 1
"
}

fn counter_increment_sql() -> String {
  "UPDATE counter SET value = value + 1 WHERE id = 1 RETURNING value
"
}

fn counter_decrement_sql() -> String {
  "UPDATE counter SET value = value - 1 WHERE id = 1 RETURNING value
"
}

fn server_context() -> String {
  "// Scaffolded by rally: yours to customize.
import sqlight

pub type ServerContext {
  ServerContext(db: sqlight.Connection)
}
"
}

fn readme(project_name: String) -> String {
  "# " <> project_name <> "

## Run

```sh
gleam run -m rally migrate
gleam run -m rally build
gleam run
```

Open http://localhost:8080.

Set `PORT` in `.env` or run `PORT=8081 gleam run` to use another port.

## Project Layout

- `src/public/pages/`: your pages. Edit `home_.gleam` or add routes here.
- `src/public/shell.html`: the HTML shell that loads the client.
- `src/sql/`: typed SQL queries for Marmot.
- `migrations/`: SQLite migrations.
- `src/server_context.gleam`: shared server resources passed to page loads and server handlers.
- `db/`: local SQLite databases created when you run the app.

## Next Steps

The scaffolded counter is disposable. It shows the request/SQL/UI loop.

- Replace the counter migration in `migrations/` with your real schema.
- Replace the counter queries in `src/sql/` with your app's queries.
- Edit `src/public/pages/home_.gleam`, or add new pages under `src/public/pages/`.
- Put shared server resources in `src/server_context.gleam`.
- Run `gleam run -m rally migrate` after changing migrations or SQL.
- Run `gleam run -m rally build` after changing pages, handlers, or shared client code.
- Start the server with `gleam run`.

## Reset the Demo Database

The scaffold stores demo app data in `db/" <> project_name <> ".db`. Rally stores its own runtime data in `db/system.db`.

To reset the demo counter, stop the server and run:

```sh
rm -f db/" <> project_name <> ".db db/" <> project_name <> ".db-wal db/" <> project_name <> ".db-shm
gleam run -m rally migrate
```

This deletes local data for this app. `rally migrate` recreates the database, applies migrations, and regenerates the typed SQL modules.
"
}
