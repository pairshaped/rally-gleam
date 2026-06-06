import gleam/list
import gleam/string
import gleeunit/should
import rally/internal/init
import simplifile
import tom

fn make_temp_dir(name: String) -> String {
  let path = "/tmp/rally_init_test_" <> name
  let _ = simplifile.delete(file_or_dir_at: path)
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn cleanup(path: String) -> Nil {
  let _ = simplifile.delete(file_or_dir_at: path)
  Nil
}

pub fn init_project_writes_hex_scaffold_test() {
  let dir = make_temp_dir("hex_scaffold")
  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  toml
  |> string.contains("name = \"rally_init_test_hex_scaffold\"")
  |> should.be_true()
  toml
  |> string.contains("rally = \">= 1.0.0 and < 2.0.0\"")
  |> should.be_true()
  toml
  |> string.contains("libero = \">= 6.0.0 and < 7.0.0\"")
  |> should.be_true()

  let assert Ok(env) = simplifile.read(dir <> "/.env")
  let assert Ok(env_example) = simplifile.read(dir <> "/.env.example")
  env |> should.equal(env_example)
  env |> string.contains("APP_ENV=dev") |> should.be_true()
  env |> string.contains("LOG_LEVEL=debug") |> should.be_true()
  env |> string.contains("PORT=8080") |> should.be_true()

  let assert Ok(gitignore) = simplifile.read(dir <> "/.gitignore")
  gitignore |> string.contains(".env") |> should.be_true()
  gitignore |> string.contains("db/") |> should.be_true()

  let assert Ok(migration) =
    simplifile.read(dir <> "/db/migrations/001_create_counter.sql")
  migration |> string.contains("CREATE TABLE counter") |> should.be_true()
  migration |> string.contains("CHECK (id = 1)") |> should.be_true()

  let assert Ok(seed) = simplifile.read(dir <> "/db/seeds/001_counter.sql")
  seed
  |> string.contains("INSERT OR IGNORE INTO counter")
  |> should.be_true()

  let assert Ok(get_sql) = simplifile.read(dir <> "/src/sql/counter/get.sql")
  get_sql |> string.contains("SELECT value FROM counter") |> should.be_true()

  let assert Ok(inc_sql) =
    simplifile.read(dir <> "/src/sql/counter/increment.sql")
  inc_sql |> string.contains("RETURNING value") |> should.be_true()

  let assert Ok(dec_sql) =
    simplifile.read(dir <> "/src/sql/counter/decrement.sql")
  dec_sql |> string.contains("value - 1") |> should.be_true()

  let assert Ok(home) = simplifile.read(dir <> "/src/public/pages/home_.gleam")
  home |> string.contains("pub fn load(") |> should.be_true()
  home |> string.contains("counter_sql") |> should.be_true()
  home |> string.contains("pub type ServerMsg") |> should.be_true()
  home |> string.contains("PublicHomeIncrement") |> should.be_true()
  home |> string.contains("pub fn handle(") |> should.be_true()

  simplifile.read(dir <> "/bin/dev")
  |> should.be_error()

  let assert Ok(toml_marmot) = simplifile.read(dir <> "/gleam.toml")
  toml_marmot
  |> string.contains("database = \"db/rally_init_test_hex_scaffold.db\"")
  |> should.be_true()

  let assert Ok(app) =
    simplifile.read(dir <> "/src/rally_init_test_hex_scaffold.gleam")
  app
  |> string.contains("bootstrap.start(")
  |> should.be_true()
  app
  |> string.contains("server_ssr.public_render_path")
  |> should.be_true()
  app |> string.contains("envoy.get(\"PORT\")") |> should.be_false()
  app |> string.contains("import rally/runtime/migrate") |> should.be_false()

  simplifile.read(dir <> "/src/app.gleam")
  |> should.be_error()

  let assert Ok(proute) = simplifile.read(dir <> "/proute.toml")
  proute |> string.contains("name = \"public\"") |> should.be_true()

  let assert Ok(public_app) = simplifile.read(dir <> "/src/public_app.gleam")
  public_app
  |> string.contains("browser_app.start_public_mount")
  |> should.be_true()

  let assert Ok(readme) = simplifile.read(dir <> "/README.md")
  readme
  |> string.contains("# rally_init_test_hex_scaffold")
  |> should.be_true()
  readme
  |> string.contains("gleam run -m rally migrate")
  |> should.be_true()
  readme
  |> string.contains("Package Version")
  |> should.be_false()
  readme
  |> string.contains("Further documentation can be found")
  |> should.be_false()

  cleanup(dir)
}

pub fn init_project_replaces_default_gleam_new_readme_test() {
  let dir = make_temp_dir("default_readme")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/README.md",
      "# rally_init_test_default_readme

[![Package Version](https://img.shields.io/hexpm/v/rally_init_test_default_readme)](https://hex.pm/packages/rally_init_test_default_readme)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/rally_init_test_default_readme/)

```sh
gleam add rally_init_test_default_readme@1
```
```gleam
import rally_init_test_default_readme

pub fn main() -> Nil {
  // TODO: An example of the project in use
}
```

Further documentation can be found at <https://hexdocs.pm/rally_init_test_default_readme>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
",
    )

  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(readme) = simplifile.read(dir <> "/README.md")
  readme |> string.contains("## Project Layout") |> should.be_true()
  readme |> string.contains("src/public/pages/") |> should.be_true()
  readme |> string.contains("Package Version") |> should.be_false()
  readme
  |> string.contains("Further documentation can be found")
  |> should.be_false()

  cleanup(dir)
}

pub fn init_project_does_not_overwrite_existing_readme_test() {
  let dir = make_temp_dir("existing_readme")
  let assert Ok(Nil) =
    simplifile.write(dir <> "/README.md", "My custom README\n")

  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(readme) = simplifile.read(dir <> "/README.md")
  readme |> should.equal("My custom README\n")

  cleanup(dir)
}

pub fn init_project_replaces_default_gleam_new_files_test() {
  let dir = make_temp_dir("default_gleam_new")
  let assert Ok(Nil) = simplifile.create_directory_all(dir <> "/src")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/src/rally_init_test_default_gleam_new.gleam",
      "import gleam/io

pub fn main() -> Nil {
  io.println(\"Hello from rally_init_test_default_gleam_new!\")
}
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/gleam.toml",
      "name = \"rally_init_test_default_gleam_new\"
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
gleam_stdlib = \">= 1.0.0 and < 2.0.0\"
rally = { path = \"/tmp/rally\" }
libero = \">= 6.0.0 and < 7.0.0\"

[dev_dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/.gitignore",
      "*.beam
*.ez
/build
erl_crash.dump
",
    )

  let assert Ok(Nil) = init.init_project(dir)
  let assert Ok(app) =
    simplifile.read(dir <> "/src/rally_init_test_default_gleam_new.gleam")
  app |> string.contains("Hello from") |> should.equal(False)
  app |> string.contains("pub fn main()") |> should.be_true()

  cleanup(dir)
}

pub fn init_project_refuses_to_overwrite_user_module_test() {
  let dir = make_temp_dir("user_module")
  let assert Ok(Nil) = simplifile.create_directory_all(dir <> "/src")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/src/rally_init_test_user_module.gleam",
      "pub fn main() -> Nil {
  Nil
}
",
    )

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains(
        "Refusing to overwrite src/rally_init_test_user_module.gleam",
      )
      |> should.be_true()
      message
      |> string.contains("fresh `gleam new` project")
      |> should.be_true()
    }
  }

  simplifile.read(dir <> "/.env")
  |> should.be_error()

  cleanup(dir)
}

pub fn init_project_refuses_empty_existing_scaffold_file_test() {
  let dir = make_temp_dir("empty_file")
  let assert Ok(Nil) = simplifile.write(dir <> "/.env", "")

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains("Refusing to overwrite .env")
      |> should.be_true()
    }
  }

  cleanup(dir)
}

pub fn init_project_refuses_existing_scaffold_directory_test() {
  let dir = make_temp_dir("directory_collision")
  let assert Ok(Nil) = simplifile.create_directory(dir <> "/.env")

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains("Refusing to overwrite .env")
      |> should.be_true()
      message
      |> string.contains("already exists as a directory")
      |> should.be_true()
    }
  }

  simplifile.read(dir <> "/src/public/pages/home_.gleam")
  |> should.be_error()

  cleanup(dir)
}

pub fn init_project_refuses_existing_migration_test() {
  let dir = make_temp_dir("existing_migration")
  let assert Ok(Nil) = simplifile.create_directory_all(dir <> "/db/migrations")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/db/migrations/001_create_counter.sql",
      "CREATE TABLE my_stuff (id INTEGER PRIMARY KEY);\n",
    )

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains(
        "Refusing to overwrite db/migrations/001_create_counter.sql",
      )
      |> should.be_true()
    }
  }

  simplifile.read(dir <> "/.env")
  |> should.be_error()

  cleanup(dir)
}

pub fn init_project_refuses_existing_sql_file_test() {
  let dir = make_temp_dir("existing_sql")
  let assert Ok(Nil) =
    simplifile.create_directory_all(dir <> "/src/sql/counter")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/src/sql/counter/get.sql",
      "SELECT * FROM my_table\n",
    )

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains("Refusing to overwrite src/sql/counter/get.sql")
      |> should.be_true()
    }
  }

  simplifile.read(dir <> "/.env")
  |> should.be_error()

  cleanup(dir)
}

pub fn init_project_refuses_existing_page_test() {
  let dir = make_temp_dir("existing_page")
  let assert Ok(Nil) =
    simplifile.create_directory_all(dir <> "/src/public/pages")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/src/public/pages/home_.gleam",
      "pub fn init() { todo }\n",
    )

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains("Refusing to overwrite src/public/pages/home_.gleam")
      |> should.be_true()
    }
  }

  simplifile.read(dir <> "/.env")
  |> should.be_error()

  cleanup(dir)
}

pub fn init_project_refuses_existing_app_shell_test() {
  let dir = make_temp_dir("existing_app_shell")
  let assert Ok(Nil) = simplifile.create_directory_all(dir <> "/src")
  let assert Ok(Nil) =
    simplifile.write(dir <> "/src/app_shell.gleam", "pub fn public(c) { c }\n")

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains("Refusing to overwrite src/app_shell.gleam")
      |> should.be_true()
    }
  }

  simplifile.read(dir <> "/.env")
  |> should.be_error()

  cleanup(dir)
}

pub fn init_project_merges_into_existing_gleam_toml_test() {
  let dir = make_temp_dir("merge_toml")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/gleam.toml",
      "name = \"rally_init_test_merge_toml\"
version = \"1.0.0\"

[dependencies]
gleam_stdlib = \">= 1.0.0 and < 2.0.0\"
rally = \">= 1.2.0 and < 2.0.0\"

[dev_dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
",
    )

  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  toml |> string.contains("target = \"erlang\"") |> should.be_true()
  toml |> string.contains("version = \"1.0.0\"") |> should.be_true()
  toml
  |> string.contains("gleam_stdlib = \">= 1.0.0 and < 2.0.0\"")
  |> should.be_true()
  toml
  |> string.contains("rally = \">= 1.2.0 and < 2.0.0\"")
  |> should.be_true()
  toml |> string.contains("envoy = ") |> should.be_true()
  toml |> string.contains("mist = ") |> should.be_true()
  toml |> string.contains("sqlight = ") |> should.be_true()
  toml |> string.contains("lustre = ") |> should.be_true()
  toml |> string.contains("marmot = ") |> should.be_true()
  toml
  |> string.contains("[tools.rally.context]")
  |> should.be_true()
  toml
  |> string.contains("database = \"db/rally_init_test_merge_toml.db\"")
  |> should.be_true()
  toml |> string.contains("[tools.glinter]") |> should.be_true()
  toml |> string.contains("birdie = ") |> should.be_true()
  toml |> string.contains("glinter = ") |> should.be_true()

  tom.parse(toml) |> should.be_ok()

  cleanup(dir)
}

pub fn init_project_merges_gleam_toml_with_different_comments_test() {
  let dir = make_temp_dir("merge_toml_alt")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/gleam.toml",
      "name = \"rally_init_test_merge_toml_alt\"
version = \"2.0.0\"

# Some totally different comment block

[dependencies]
gleam_stdlib = \">= 0.50.0 and < 1.0.0\"

[dev-dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
",
    )

  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  toml |> string.contains("target = \"erlang\"") |> should.be_true()
  toml |> string.contains("version = \"2.0.0\"") |> should.be_true()
  toml
  |> string.contains("# Some totally different comment block")
  |> should.be_true()
  toml
  |> string.contains("gleam_stdlib = \">= 0.50.0 and < 1.0.0\"")
  |> should.be_true()
  toml |> string.contains("envoy = ") |> should.be_true()
  toml |> string.contains("[tools.marmot]") |> should.be_true()

  tom.parse(toml) |> should.be_ok()

  cleanup(dir)
}

pub fn init_project_merges_gleam_toml_with_trailing_spaces_test() {
  let dir = make_temp_dir("merge_toml_spaces")
  let dep_header = "[dependencies]   "
  let dev_dep_header = "[dev_dependencies]  "
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/gleam.toml",
      "name = \"rally_init_test_merge_toml_spaces\"\nversion = \"1.0.0\"\n\n"
        <> dep_header
        <> "\ngleam_stdlib = \">= 1.0.0 and < 2.0.0\"\n\n"
        <> dev_dep_header
        <> "\ngleeunit = \">= 1.0.0 and < 2.0.0\"\n",
    )

  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  toml |> string.contains("envoy = ") |> should.be_true()
  toml |> string.contains("birdie = ") |> should.be_true()
  tom.parse(toml) |> should.be_ok()

  cleanup(dir)
}

pub fn init_project_merges_gleam_toml_with_crlf_test() {
  let dir = make_temp_dir("merge_toml_crlf")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/gleam.toml",
      "name = \"rally_init_test_merge_toml_crlf\"\r\nversion = \"1.0.0\"\r\n\r\n[dependencies]\r\ngleam_stdlib = \">= 1.0.0 and < 2.0.0\"\r\n\r\n[dev_dependencies]\r\ngleeunit = \">= 1.0.0 and < 2.0.0\"\r\n",
    )

  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  toml |> string.contains("envoy = ") |> should.be_true()
  toml |> string.contains("target = \"erlang\"") |> should.be_true()
  tom.parse(toml) |> should.be_ok()

  cleanup(dir)
}

pub fn init_project_refuses_invalid_gleam_toml_without_writing_test() {
  let dir = make_temp_dir("invalid_toml")
  let assert Ok(Nil) =
    simplifile.write(dir <> "/gleam.toml", "this is not [ valid toml")

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message |> string.contains("syntax errors") |> should.be_true()
    }
  }

  simplifile.read(dir <> "/.env") |> should.be_error()

  cleanup(dir)
}

pub fn init_project_refuses_inline_dep_tables_without_writing_test() {
  let dir = make_temp_dir("inline_deps")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/gleam.toml",
      "name = \"rally_init_test_inline_deps\"
version = \"1.0.0\"
dependencies = { gleam_stdlib = \">= 1.0.0 and < 2.0.0\" }

[dev_dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
",
    )

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message |> string.contains("inline dependency tables") |> should.be_true()
    }
  }

  simplifile.read(dir <> "/.env") |> should.be_error()

  cleanup(dir)
}

pub fn init_project_adds_rally_context_when_missing_test() {
  let dir = make_temp_dir("missing_rally_context")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/gleam.toml",
      "name = \"rally_init_test_non_public_client\"
version = \"1.0.0\"

[dependencies]
gleam_stdlib = \">= 1.0.0 and < 2.0.0\"

[dev_dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"

[tools.rally.push]
module = \"broadcasts\"
type = \"Event\"
",
    )

  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  toml
  |> string.contains("[tools.rally.push]")
  |> should.be_true()
  toml
  |> string.contains("[tools.rally.context]")
  |> should.be_true()
  tom.parse(toml) |> should.be_ok()

  cleanup(dir)
}

pub fn init_project_skips_rally_context_when_already_exists_test() {
  let dir = make_temp_dir("has_rally_context")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/gleam.toml",
      "name = \"rally_init_test_has_public_client\"
version = \"1.0.0\"

[dependencies]
gleam_stdlib = \">= 1.0.0 and < 2.0.0\"

[dev_dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"

[tools.rally.context]
module = \"my/context\"
type = \"Context\"
",
    )

  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  let context_count =
    toml
    |> string.split("[tools.rally.context]")
    |> list.length
  context_count |> should.equal(2)
  tom.parse(toml) |> should.be_ok()

  cleanup(dir)
}

pub fn init_project_merges_gitignore_test() {
  let dir = make_temp_dir("merge_gitignore")
  let assert Ok(Nil) =
    simplifile.write(dir <> "/.gitignore", "*.beam\n*.ez\n/build\n")

  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(gitignore) = simplifile.read(dir <> "/.gitignore")
  gitignore |> string.contains("*.beam") |> should.be_true()
  gitignore |> string.contains("/build") |> should.be_true()
  gitignore |> string.contains(".env") |> should.be_true()
  gitignore |> string.contains("db/") |> should.be_true()
  gitignore |> string.contains(".DS_Store") |> should.be_true()

  cleanup(dir)
}

pub fn init_project_idempotent_gleam_toml_test() {
  let dir = make_temp_dir("idempotent_toml")
  let assert Ok(Nil) = init.init_project(dir)
  let assert Ok(first_toml) = simplifile.read(dir <> "/gleam.toml")
  let assert Ok(first_gitignore) = simplifile.read(dir <> "/.gitignore")

  let _ = simplifile.delete(file_or_dir_at: dir)
  let assert Ok(Nil) = simplifile.create_directory_all(dir)
  let assert Ok(Nil) = simplifile.write(dir <> "/gleam.toml", first_toml)
  let assert Ok(Nil) = simplifile.write(dir <> "/.gitignore", first_gitignore)

  let assert Ok(Nil) = init.init_project(dir)
  let assert Ok(second_toml) = simplifile.read(dir <> "/gleam.toml")
  let assert Ok(second_gitignore) = simplifile.read(dir <> "/.gitignore")

  first_toml |> should.equal(second_toml)
  first_gitignore |> should.equal(second_gitignore)
  tom.parse(second_toml) |> should.be_ok()

  cleanup(dir)
}
