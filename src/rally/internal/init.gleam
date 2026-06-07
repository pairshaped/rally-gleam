import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import simplifile
import tom.{type Toml}

pub type ScaffoldFile {
  ScaffoldFile(path: String, contents: String)
}

pub fn init_project(root: String) -> Result(Nil, String) {
  let name = project_name(root)
  let scaffold_files = files(name)

  use toml_content <- result.try(prepare_gleam_toml(root, name))
  use Nil <- result.try(ensure_safe_to_write(root, name, scaffold_files))
  use Nil <- result.try(create_dirs(root))
  use Nil <- result.try(write_files(root, scaffold_files))
  use Nil <- result.try(write_gleam_toml(root, toml_content))
  use Nil <- result.try(merge_gitignore(root))
  write_readme_if_missing(root, name)
  Ok(Nil)
}

pub fn files(project_name: String) -> List(ScaffoldFile) {
  [
    ScaffoldFile(".env", env_example()),
    ScaffoldFile(".env.example", env_example()),
    ScaffoldFile("db/migrations/001_create_counter.sql", migration_001()),
    ScaffoldFile("db/seeds/001_counter.sql", seed_001()),
    ScaffoldFile("src/sql/counter/get.sql", counter_get_sql()),
    ScaffoldFile("src/sql/counter/increment.sql", counter_increment_sql()),
    ScaffoldFile("src/sql/counter/decrement.sql", counter_decrement_sql()),
    ScaffoldFile("src/public/pages/home_.gleam", home_page()),
    ScaffoldFile("src/public/pages/not_found_.gleam", not_found_page()),
    ScaffoldFile("src/public/page_shared_state.gleam", page_shared_state()),
    ScaffoldFile("src/app_shell.gleam", app_shell()),
    ScaffoldFile("src/app_ws.gleam", app_ws()),
    ScaffoldFile("src/public_app.gleam", public_app()),
    ScaffoldFile("src/" <> project_name <> ".gleam", app_module(project_name)),
    ScaffoldFile("proute.toml", proute_toml()),
  ]
}

fn create_dirs(root: String) -> Result(Nil, String) {
  [
    "db/migrations",
    "db/seeds",
    "db",
    "src/public/pages",
    "src/sql/counter",
    "src/generated",
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
  case path == "src/" <> project_name <> ".gleam" {
    True -> existing == "import gleam/io

pub fn main() -> Nil {
  io.println(\"Hello from " <> project_name <> "!\")
}
"
    False -> False
  }
}

fn prepare_gleam_toml(
  root: String,
  project_name: String,
) -> Result(String, String) {
  let path = join(root, "gleam.toml")
  use content <- result.try(case simplifile.read(path) {
    Ok(existing) -> merge_into_gleam_toml(existing, project_name)
    Error(_) -> Ok(gleam_toml(project_name))
  })
  use _ <- result.try(
    tom.parse(content)
    |> result.map_error(fn(_) {
      "Rally produced an invalid gleam.toml merge. This can happen if the existing file uses inline dependency tables. Restructure gleam.toml to use [dependencies] and [dev-dependencies] section headers, then retry."
    }),
  )
  Ok(content)
}

fn write_gleam_toml(root: String, content: String) -> Result(Nil, String) {
  let path = join(root, "gleam.toml")
  simplifile.write(to: path, contents: content)
  |> result.map_error(fn(e) {
    "Failed to write gleam.toml: " <> simplifile.describe_error(e)
  })
}

fn merge_into_gleam_toml(
  existing: String,
  project_name: String,
) -> Result(String, String) {
  use parsed <- result.try(
    tom.parse(existing)
    |> result.map_error(fn(_) {
      "gleam.toml has syntax errors. Fix them and try again."
    }),
  )

  let missing_deps =
    required_deps()
    |> list.filter_map(fn(dep) {
      let #(name, version) = dep
      case tom.get(parsed, ["dependencies", name]) {
        Ok(_) -> Error(Nil)
        Error(_) -> Ok(name <> " = \"" <> version <> "\"")
      }
    })

  let missing_dev_deps =
    required_dev_deps()
    |> list.filter_map(fn(dep) {
      let #(name, version) = dep
      let exists =
        result.is_ok(tom.get(parsed, ["dev-dependencies", name]))
        || result.is_ok(tom.get(parsed, ["dev_dependencies", name]))
      case exists {
        True -> Error(Nil)
        False -> Ok(name <> " = \"" <> version <> "\"")
      }
    })

  existing
  |> string.replace("\r\n", "\n")
  |> ensure_target(parsed)
  |> add_entries_to_section("[dependencies]", missing_deps)
  |> add_entries_to_section(dev_deps_section_header(existing), missing_dev_deps)
  |> ensure_tool_sections(parsed, project_name)
  |> Ok
}

fn ensure_target(content: String, parsed: Dict(String, Toml)) -> String {
  case tom.get(parsed, ["target"]) {
    Ok(_) -> content
    Error(_) -> {
      let lines = string.split(content, "\n")
      string.join(
        insert_line_after(lines, "version = ", "target = \"erlang\""),
        "\n",
      )
    }
  }
}

fn insert_line_after(
  lines: List(String),
  prefix: String,
  new_line: String,
) -> List(String) {
  case lines {
    [] -> [new_line]
    [line, ..rest] ->
      case string.starts_with(string.trim(line), prefix) {
        True -> [line, new_line, ..rest]
        False -> [line, ..insert_line_after(rest, prefix, new_line)]
      }
  }
}

fn add_entries_to_section(
  content: String,
  section_header: String,
  entries: List(String),
) -> String {
  case entries {
    [] -> content
    _ -> {
      let lines = string.split(content, "\n")
      case do_insert_in_section(lines, section_header, entries, []) {
        Ok(new_lines) -> string.join(new_lines, "\n")
        Error(Nil) -> {
          let entries_text = string.join(entries, "\n")
          string.trim_end(content)
          <> "\n\n"
          <> section_header
          <> "\n"
          <> entries_text
          <> "\n"
        }
      }
    }
  }
}

fn do_insert_in_section(
  lines: List(String),
  section_header: String,
  entries: List(String),
  acc: List(String),
) -> Result(List(String), Nil) {
  case lines {
    [] -> Error(Nil)
    [line, ..rest] ->
      case is_section_header(line, section_header) {
        True -> {
          let #(body, remaining) = take_section_body(rest)
          let trimmed = drop_trailing_blanks(body)
          Ok(
            list.flatten([
              list.reverse(acc),
              [line],
              trimmed,
              entries,
              [""],
              remaining,
            ]),
          )
        }
        False ->
          do_insert_in_section(rest, section_header, entries, [line, ..acc])
      }
  }
}

fn is_section_header(line: String, expected: String) -> Bool {
  let trimmed = string.trim(line)
  trimmed == expected
  || {
    string.starts_with(trimmed, expected)
    && {
      let rest = string.drop_start(trimmed, string.length(expected))
      string.starts_with(rest, " ")
      || string.starts_with(rest, "\t")
      || string.starts_with(rest, "#")
    }
  }
}

fn take_section_body(lines: List(String)) -> #(List(String), List(String)) {
  do_take_section_body(lines, [])
}

fn do_take_section_body(
  lines: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case lines {
    [] -> #(list.reverse(acc), [])
    [line, ..rest] ->
      case string.starts_with(string.trim_start(line), "[") {
        True -> #(list.reverse(acc), [line, ..rest])
        False -> do_take_section_body(rest, [line, ..acc])
      }
  }
}

fn drop_trailing_blanks(lines: List(String)) -> List(String) {
  lines
  |> list.reverse
  |> list.drop_while(fn(line) { string.trim(line) == "" })
  |> list.reverse
}

fn dev_deps_section_header(content: String) -> String {
  case string.contains(content, "[dev-dependencies]") {
    True -> "[dev-dependencies]"
    False ->
      case string.contains(content, "[dev_dependencies]") {
        True -> "[dev_dependencies]"
        False -> "[dev-dependencies]"
      }
  }
}

fn ensure_tool_sections(
  content: String,
  parsed: Dict(String, Toml),
  project_name: String,
) -> String {
  content
  |> ensure_glinter_section(parsed)
  |> ensure_rally_context_section(parsed)
  |> ensure_marmot_section(parsed, project_name)
}

fn ensure_glinter_section(
  content: String,
  parsed: Dict(String, Toml),
) -> String {
  case tom.get(parsed, ["tools", "glinter"]) {
    Ok(_) -> content
    Error(_) ->
      string.trim_end(content)
      <> "\n\n[tools.glinter]\nstats = true\nwarnings_as_errors = true\nexclude = [\"src/generated/\"]\n"
  }
}

fn ensure_rally_context_section(
  content: String,
  parsed: Dict(String, Toml),
) -> String {
  case tom.get(parsed, ["tools", "rally", "context"]) {
    Ok(_) -> content
    Error(_) ->
      string.trim_end(content)
      <> "\n\n[tools.rally.context]\nmodule = \"sqlight\"\ntype = \"Connection\"\n"
  }
}

fn ensure_marmot_section(
  content: String,
  parsed: Dict(String, Toml),
  project_name: String,
) -> String {
  case tom.get(parsed, ["tools", "marmot"]) {
    Ok(_) -> content
    Error(_) ->
      string.trim_end(content)
      <> "\n\n[tools.marmot]\ndatabase = \"db/"
      <> project_name
      <> ".db\"\nsql_dir = \"src/sql\"\noutput = \"src/generated/sql\"\n"
  }
}

fn required_deps() -> List(#(String, String)) {
  [
    #("envoy", ">= 1.2.0 and < 2.0.0"),
    #("gleam_erlang", ">= 1.0.0 and < 2.0.0"),
    #("gleam_http", ">= 4.0.0 and < 5.0.0"),
    #("gleam_stdlib", ">= 0.60.0 and < 2.0.0"),
    #("rally", ">= 2.0.0 and < 3.0.0"),
    #("libero", ">= 7.0.0 and < 8.0.0"),
    #("lustre", ">= 5.7.0 and < 7.0.0"),
    #("mist", ">= 6.0.0 and < 7.0.0"),
    #("sqlight", ">= 1.0.0 and < 2.0.0"),
    #("simplifile", ">= 2.0.0 and < 3.0.0"),
    #("gleam_time", ">= 1.7.0 and < 2.0.0"),
  ]
}

fn required_dev_deps() -> List(#(String, String)) {
  [
    #("gleeunit", ">= 1.0.0 and < 2.0.0"),
    #("birdie", ">= 2.0.0 and < 3.0.0"),
    #("glinter", ">= 2.16.0 and < 3.0.0"),
    #("marmot", ">= 1.3.0 and < 2.0.0"),
  ]
}

fn merge_gitignore(root: String) -> Result(Nil, String) {
  let path = join(root, ".gitignore")
  let existing = simplifile.read(path) |> result.unwrap("")
  let existing_lines =
    existing
    |> string.split("\n")
    |> list.map(string.trim)

  let required = [
    "build/", ".env", "db/", "erl_crash.dump", "*.bak", ".DS_Store",
  ]
  let missing =
    required
    |> list.filter(fn(line) { !list.contains(existing_lines, line) })

  case missing {
    [] -> Ok(Nil)
    _ -> {
      let content = case existing {
        "" -> string.join(missing, "\n") <> "\n"
        _ ->
          string.trim_end(existing)
          <> "\n"
          <> string.join(missing, "\n")
          <> "\n"
      }
      simplifile.write(to: path, contents: content)
      |> result.map_error(fn(e) {
        "Failed to write .gitignore: " <> simplifile.describe_error(e)
      })
    }
  }
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
libero = \">= 7.0.0 and < 8.0.0\"
lustre = \">= 5.7.0 and < 7.0.0\"
mist = \">= 6.0.0 and < 7.0.0\"
sqlight = \">= 1.0.0 and < 2.0.0\"
simplifile = \">= 2.0.0 and < 3.0.0\"
gleam_time = \">= 1.7.0 and < 2.0.0\"

[dev-dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
birdie = \">= 2.0.0 and < 3.0.0\"
glinter = \">= 2.16.0 and < 3.0.0\"
marmot = \">= 1.3.0 and < 2.0.0\"

[tools.glinter]
stats = true
warnings_as_errors = true
exclude = [\"src/generated/\"]

[tools.rally.context]
module = \"sqlight\"
type = \"Connection\"

[tools.marmot]
database = \"db/" <> project_name <> ".db\"
sql_dir = \"src/sql\"
output = \"src/generated/sql\"
"
}

fn home_page() -> String {
  "// Scaffolded by rally: yours to customize.
@target(erlang)
import generated/sql/counter_sql
import gleam/int
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/effect.{type Effect}
import lustre/event
import generated/proute/public/page_input
import public/page_shared_state.{type PublicPageSharedState}
import rally/runtime/load as runtime_load

@target(erlang)
import sqlight

@target(javascript)
import generated/rally/server

pub type ServerMsg {
  PublicHomeLoad
  PublicHomeIncrement
  PublicHomeDecrement
}

pub type LoadResult {
  PublicHomeLoaded(count: Int)
}

pub type CounterUpdate {
  CounterUpdate(count: Int)
}

pub type SaveError {
  SaveError(message: String)
}

pub type Model {
  Model(count: Int, error: String)
}

pub type Message {
  Increment
  Decrement
  Loaded(Result(Int, runtime_load.LoadError))
  Saved(Result(CounterUpdate, SaveError))
}

pub fn initial_model(
  _page_shared_state: PublicPageSharedState,
  _query_params: page_input.QueryParams,
) -> Model {
  Model(count: 0, error: \"\")
}

pub fn update(model: Model, msg: Message) -> #(Model, Effect(Message)) {
  case msg {
    Increment | Decrement -> #(model, save_effect(msg))
    Loaded(Ok(count)) -> #(Model(count:, error: \"\"), effect.none())
    Loaded(Error(error)) -> #(
      Model(..model, error: error.message),
      effect.none(),
    )
    Saved(Ok(CounterUpdate(count:))) -> #(
      Model(count:, error: \"\"),
      effect.none(),
    )
    Saved(Error(SaveError(message:))) -> #(
      Model(..model, error: message),
      effect.none(),
    )
  }
}

pub fn view(model: Model) -> Element(Message) {
  html.main([attribute.class(\"counter-page\")], [
    html.h1([], [html.text(\"Rally Counter\")]),
    html.div([attribute.class(\"counter\")], [
      html.button([event.on_click(Decrement)], [html.text(\"-\")]),
      html.strong([], [html.text(int.to_string(model.count))]),
      html.button([event.on_click(Increment)], [html.text(\"+\")]),
    ]),
    case model.error {
      \"\" -> html.text(\"\")
      message -> html.p([attribute.class(\"error\")], [html.text(message)])
    },
  ])
}

@target(javascript)
fn save_effect(msg: Message) -> Effect(Message) {
  case msg {
    Increment ->
      server.save_public_home(
        message: PublicHomeIncrement,
        on_result: fn(result) { Saved(map_save_result(result)) },
      )
    Decrement ->
      server.save_public_home(
        message: PublicHomeDecrement,
        on_result: fn(result) { Saved(map_save_result(result)) },
      )
    Loaded(_) | Saved(_) -> effect.none()
  }
}

@target(erlang)
fn save_effect(_msg: Message) -> Effect(Message) {
  effect.none()
}

@target(javascript)
fn map_save_result(
  result: Result(CounterUpdate, List(server.SaveError)),
) -> Result(CounterUpdate, SaveError) {
  case result {
    Ok(update) -> Ok(update)
    Error([server.SaveError(message: message, ..), ..]) ->
      Error(SaveError(message:))
    Error([]) -> Error(SaveError(message: \"Could not save counter.\"))
  }
}

@target(erlang)
pub fn load(db: sqlight.Connection) -> Result(Int, runtime_load.LoadError) {
  case counter_sql.get(db:) {
    Ok([row]) -> Ok(row.value)
    _ -> Error(runtime_load.LoadError(message: \"Could not load counter.\"))
  }
}

@target(erlang)
pub fn handle_save(
  db: sqlight.Connection,
  message: ServerMsg,
) -> Result(CounterUpdate, SaveError) {
  case message {
    PublicHomeLoad ->
      Error(SaveError(message: \"Load is not a save action.\"))
    PublicHomeIncrement -> save_increment(counter_sql.increment(db:))
    PublicHomeDecrement -> save_decrement(counter_sql.decrement(db:))
  }
}

@target(erlang)
fn save_increment(
  result: Result(List(counter_sql.IncrementRow), sqlight.Error),
) -> Result(CounterUpdate, SaveError) {
  case result {
    Ok([row]) -> Ok(CounterUpdate(count: row.value))
    _ -> Error(SaveError(message: \"Could not save counter.\"))
  }
}

@target(erlang)
fn save_decrement(
  result: Result(List(counter_sql.DecrementRow), sqlight.Error),
) -> Result(CounterUpdate, SaveError) {
  case result {
    Ok([row]) -> Ok(CounterUpdate(count: row.value))
    _ -> Error(SaveError(message: \"Could not save counter.\"))
  }
}
"
}

fn page_shared_state() -> String {
  "// Scaffolded by rally: yours to customize.

pub type PublicPageSharedState {
  PublicPageSharedState
}
"
}

fn not_found_page() -> String {
  "// Scaffolded by rally: yours to customize.
import generated/proute/public/page_input
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import public/page_shared_state.{type PublicPageSharedState}

pub type Model {
  Model
}

pub type Message {
  NoOp
}

pub fn initial_model(
  _page_shared_state: PublicPageSharedState,
  _query_params: page_input.QueryParams,
) -> Model {
  Model
}

pub fn update(
  model: Model,
  _msg: Message,
) -> #(Model, Effect(Message)) {
  #(model, effect.none())
}

pub fn view(_model: Model) -> Element(Message) {
  html.main([attribute.class(\"not-found\")], [
    html.h1([], [html.text(\"Not found\")]),
    html.p([], [html.text(\"No route matched this page.\")]),
  ])
}
"
}

fn app_shell() -> String {
  "// Scaffolded by rally: yours to customize.
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn public(
  current_path current_path: String,
  dark_mode dark_mode: Bool,
  on_dark_mode_change on_dark_mode_change: fn(Bool) -> msg,
  content content: Element(msg),
) -> Element(msg) {
  html.div([attribute.class(\"app\")], [
    html.header([attribute.class(\"topbar\")], [
      html.a(
        [
          attribute.href(\"/\"),
        ],
        [html.text(\"Rally\")],
      ),
      html.span([attribute.class(\"current-path\")], [html.text(current_path)]),
      html.button(
        [event.on_click(on_dark_mode_change(!dark_mode))],
        [html.text(theme_label(dark_mode))],
      ),
    ]),
    content,
  ])
}

fn theme_label(dark_mode: Bool) -> String {
  case dark_mode {
    True -> \"Light\"
    False -> \"Dark\"
  }
}
"
}

fn app_ws() -> String {
  "@target(erlang)
import generated/rally/server_ws
@target(erlang)
import gleam/erlang/process.{type Selector}
@target(erlang)
import gleam/option.{type Option, None}
@target(erlang)
import mist.{type Next, type WebsocketConnection, type WebsocketMessage}
@target(erlang)
import sqlight

@target(javascript)
pub fn ensure() -> Nil {
  Nil
}

@target(erlang)
pub type State =
  server_ws.ConnectionState(Nil)

@target(erlang)
pub fn on_init(
  _conn: WebsocketConnection,
  db: sqlight.Connection,
) -> #(State, Option(Selector(BitArray))) {
  server_ws.on_init(load_context: db, admin_auth: None)
}

@target(erlang)
pub fn on_close(state: State) -> Nil {
  server_ws.on_close(state)
}

@target(erlang)
pub fn handler(
  state state: State,
  msg msg: WebsocketMessage(BitArray),
  conn conn: WebsocketConnection,
) -> Next(State, BitArray) {
  server_ws.handler(state:, msg:, conn:)
}
"
}

fn public_app() -> String {
  "@target(javascript)
import app_shell
@target(javascript)
import generated/proute/public/pages
@target(javascript)
import generated/rally/browser_app
@target(javascript)
import lustre/element.{type Element, map}
@target(javascript)
import public/page_shared_state.{PublicPageSharedState}

@target(javascript)
pub type ShellState {
  ShellState(current_path: String, dark_mode: Bool)
}

@target(javascript)
pub fn main() -> Nil {
  browser_app.start_public_mount(browser_app.PublicMountConfig(
    page_shared_state: fn() { PublicPageSharedState },
    shell_state: fn(current_path, dark_mode) {
      ShellState(current_path:, dark_mode:)
    },
    set_active_path: fn(shell_state, path) {
      ShellState(..shell_state, current_path: path)
    },
    set_dark_mode: fn(shell_state, dark_mode) {
      ShellState(..shell_state, dark_mode:)
    },
    update_page: fn(_page_shared_state, page, message) {
      pages.update(page, message)
    },
    view:,
  ))
}

@target(erlang)
pub fn ensure() -> Nil {
  Nil
}

@target(javascript)
fn view(
  model: browser_app.PublicMountModel(ShellState),
  on_page: fn(pages.Message) -> browser_app.PublicMountMsg,
  on_dark_mode_change: fn(Bool) -> browser_app.PublicMountMsg,
  _on_navigate: fn(String) -> browser_app.PublicMountMsg,
) -> Element(browser_app.PublicMountMsg) {
  app_shell.public(
    current_path: model.shell_state.current_path,
    dark_mode: model.shell_state.dark_mode,
    on_dark_mode_change:,
    content: pages.view(model.page) |> map(on_page),
  )
}
"
}

fn proute_toml() -> String {
  "[proute]
pages_root = \"src\"

[[proute.mounts]]
name = \"public\"
route_root = \"/\"
"
}

fn app_module(project_name: String) -> String {
  "@target(erlang)
import app_shell
@target(erlang)
import app_ws
@target(erlang)
import generated/proute/public/page_input
@target(erlang)
import generated/rally/server_ssr
@target(erlang)
import generated/rally/theme
@target(erlang)
import gleam/bytes_tree
@target(erlang)
import gleam/http/request.{type Request}
@target(erlang)
import gleam/http/response.{type Response}
@target(erlang)
import lustre/element
@target(erlang)
import mist.{type Connection, type ResponseData}
@target(erlang)
import public/page_shared_state.{PublicPageSharedState}
@target(erlang)
import rally/runtime/bootstrap
@target(erlang)
import rally/runtime/document

@target(erlang)
pub fn main() -> Nil {
  case
    bootstrap.start(
      default_port: 8080,
      handlers: bootstrap.Handlers(
        auth: handle_auth_path,
        websocket: handle_websocket_path,
        admin: handle_admin_path,
        public: handle_public_path,
      ),
    )
  {
    Ok(Nil) -> Nil
    Error(error) -> panic as bootstrap.start_error_message(error)
  }
}

@target(erlang)
fn handle_auth_path(
  _req: Request(Connection),
  _context: bootstrap.Context,
) -> Result(Response(ResponseData), Nil) {
  Error(Nil)
}

@target(erlang)
fn handle_websocket_path(
  req req: Request(Connection),
  context context: bootstrap.Context,
) -> Response(ResponseData) {
  mist.websocket(
    req,
    app_ws.handler,
    fn(conn) { app_ws.on_init(conn, context.db) },
    app_ws.on_close,
  )
}

@target(erlang)
fn handle_admin_path(
  _req: Request(Connection),
  _context: bootstrap.Context,
) -> Response(ResponseData) {
  not_found()
}

@target(erlang)
fn handle_public_path(
  req req: Request(Connection),
  context context: bootstrap.Context,
) -> Response(ResponseData) {
  let page =
    server_ssr.public_render_path(
      page_shared_state: PublicPageSharedState,
      query_params: query_params(req),
      path: req.path,
      load_context: context.db,
    )

  let html =
    app_shell.public(
      current_path: page.current_path,
      dark_mode: theme.request_dark_mode(req),
      on_dark_mode_change: fn(_) { Nil },
      content: page.content,
    )
    |> element.to_string

  let document_html =
    \"<!doctype html>
<html \" <> theme.document_attribute(req) <> \">
<head>
  <meta charset=\\\"utf-8\\\">
  <meta name=\\\"viewport\\\" content=\\\"width=device-width, initial-scale=1\\\">
  <title>Rally</title>
</head>
<body>
  <div id=\\\"app\\\"\" <> document.hydration_attr(page.hydration) <> \">\" <> html <> \"</div>
  <script type=\\\"module\\\">
    import { main } from '/_build/" <> project_name <> "/public_app.mjs';
    main();
  </script>
</body>
</html>\"

  document.html_response(document_html)
}

@target(erlang)
fn query_params(req: Request(Connection)) -> page_input.QueryParams {
  document.query_params(
    req:,
    from_values: fn(values) { page_input.QueryParams(values:) },
    empty: page_input.empty_query_params,
  )
}

@target(erlang)
fn not_found() -> Response(ResponseData) {
  response.new(404)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(\"Not found\")))
}

@target(javascript)
pub fn ensure() -> Nil {
  Nil
}
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

fn seed_001() -> String {
  "INSERT OR IGNORE INTO counter (id, value) VALUES (1, 0);
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

fn readme(project_name: String) -> String {
  "# " <> project_name <> "

## Run

```sh
gleam run -m rally migrate
gleam run -m rally build
gleam run -m rally server
```

Open http://localhost:8080.

Set `PORT` in `.env` or run `PORT=8081 gleam run -m rally server` to use another port.

`rally server` stops any process already listening on `PORT` or 8080, then runs the app in the foreground. Use Ctrl-C to stop it.

## Project Layout

- `src/public/pages/`: your pages. Edit `home_.gleam` or add routes here.
- `src/sql/`: typed SQL queries for Marmot.
- `db/migrations/`: SQLite migrations run by Marmot.
- `db/seeds/`: optional seed files run by Marmot reset.
- `src/public/page_shared_state.gleam`: shared page state for this mount.
- `src/generated/`: Proute, Rally, Libero, and SQL code written by generators.
- `db/`: local SQLite databases created when you run the app.

## Next Steps

The scaffolded counter is disposable. It shows the request/SQL/UI loop.

- Replace the counter migration in `db/migrations/` with your real schema.
- Replace the counter queries in `src/sql/` with your app's queries.
- Edit `src/public/pages/home_.gleam`, or add new pages under `src/public/pages/`.
- Put app-wide server resources in the load context configured in `gleam.toml`.
- Run `gleam run -m rally migrate` after changing migrations or SQL.
- Run `gleam run -m rally reset` to drop the local database, run migrations, and run seeds.
- Run `gleam run -m rally regen` when you want to delete and recreate `src/generated/`.
- Run `gleam run -m rally build` after changing pages, handlers, or shared client code.
- Start the server with `gleam run -m rally server`.

## Reset the Demo Database

The scaffold stores demo app data in `db/" <> project_name <> ".db`. Rally stores its own runtime data in `db/system.db`.

To reset the demo counter, stop the server and run:

```sh
gleam run -m rally reset
```

This deletes local data for this app. `rally reset` delegates to Marmot, which recreates the database, applies configured migrations, and runs configured seeds.
"
}
