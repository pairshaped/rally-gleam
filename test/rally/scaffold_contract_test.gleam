import gleam/string
import gleeunit/should
import rally/internal/init
import simplifile

pub fn scaffold_uses_rally_bootstrap_and_page_contract_test() {
  let script = scaffold_source()

  script
  |> string.contains("bootstrap.start(")
  |> should.equal(True)

  script
  |> string.contains("server_ssr.public_render_path")
  |> should.equal(True)

  script
  |> string.contains("browser_app.start_public_mount")
  |> should.equal(True)

  script
  |> string.contains("PublicPageSharedState")
  |> should.equal(True)

  script
  |> string.contains("document.hydration_attr")
  |> should.equal(True)

  script
  |> string.contains("gleam run\n")
  |> should.equal(False)

  script
  |> string.contains("pub type ServerMsg")
  |> should.equal(True)

  script
  |> string.contains("PublicHomeLoad")
  |> should.equal(True)

  script
  |> string.contains("pub fn initial_model(")
  |> should.equal(True)

  script
  |> string.contains("pub fn update(model: Model, msg: Message)")
  |> should.equal(True)

  script
  |> string.contains("pub fn handle_save(")
  |> should.equal(True)

  script
  |> string.contains("import rally/runtime/migrate")
  |> should.equal(False)

  script
  |> string.contains("migrate.run")
  |> should.equal(False)
}

pub fn scaffold_uses_proute_and_rally_context_config_test() {
  let dir = "/tmp/rally_scaffold_contract_ns_fresh"
  let _ = simplifile.delete(file_or_dir_at: dir)
  let assert Ok(Nil) = simplifile.create_directory_all(dir)
  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  toml
  |> string.contains("[tools.rally.context]")
  |> should.equal(True)
  toml |> string.contains("module = \"sqlight\"") |> should.equal(True)
  toml |> string.contains("type = \"Connection\"") |> should.equal(True)
  toml |> string.contains("proute = ") |> should.equal(False)

  let assert Ok(proute) = simplifile.read(dir <> "/proute.toml")
  proute |> string.contains("[proute]") |> should.equal(True)
  proute |> string.contains("pages_root = \"src\"") |> should.equal(True)
  proute |> string.contains("name = \"public\"") |> should.equal(True)

  let _ = simplifile.delete(file_or_dir_at: dir)
  Nil
}

pub fn scaffold_uses_websocket_load_save_instead_of_http_rpc_test() {
  let script = scaffold_source()

  script
  |> string.contains("import generated/public/http_handler as http_handler")
  |> should.equal(False)

  script
  |> string.contains("\"/rpc\" ->")
  |> should.equal(False)

  script
  |> string.contains("mist.read_body(req, max_body_limit: 16_000_000)")
  |> should.equal(False)

  script
  |> string.contains("server.save_public_home")
  |> should.equal(True)

  script
  |> string.contains("server_ws.on_init(load_context: db")
  |> should.equal(True)

  script
  |> string.contains("http_handler.handle(")
  |> should.equal(False)
}

pub fn scaffold_does_not_import_rally_runtime_test() {
  let script = scaffold_source()

  script
  |> string.contains("import rally_runtime/")
  |> should.equal(False)
}

fn scaffold_source() -> String {
  let dir = "/tmp/rally_scaffold_contract_fresh"
  let _ = simplifile.delete(file_or_dir_at: dir)
  let assert Ok(Nil) = simplifile.create_directory_all(dir)
  let assert Ok(Nil) = init.init_project(dir)
  let assert Ok(home_page) =
    simplifile.read(dir <> "/src/public/pages/home_.gleam")
  let assert Ok(app) =
    simplifile.read(dir <> "/src/rally_scaffold_contract_fresh.gleam")
  let assert Ok(public_app) = simplifile.read(dir <> "/src/public_app.gleam")
  let assert Ok(app_ws) = simplifile.read(dir <> "/src/app_ws.gleam")
  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  let assert Ok(proute) = simplifile.read(dir <> "/proute.toml")
  let _ = simplifile.delete(file_or_dir_at: dir)
  string.join([home_page, app, public_app, app_ws, toml, proute], "\n")
}
