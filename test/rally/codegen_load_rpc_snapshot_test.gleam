import birdie
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import rally/internal/format
import rally/internal/generator/load_rpc.{
  type GeneratedFile, type LoadContext, type LoadRpc, type PushContract,
  GeneratedFile, LoadArg, LoadContext, LoadRpc, PushContract, discover, generate,
  libero_type_seeds, result_module,
}
import simplifile

fn public_games_load() -> LoadRpc {
  LoadRpc(
    name: "public_games",
    module_path: "public/pages/games",
    wire_module: "public/pages/games/wire",
    import_on_client: True,
    request_constructor: "PublicGamesLoad",
    args: [],
    save_result_type: None,
  )
}

fn public_game_detail_load() -> LoadRpc {
  LoadRpc(
    name: "public_game_detail",
    module_path: "public/pages/games/id_",
    wire_module: "public/pages/games/id_/wire",
    import_on_client: True,
    request_constructor: "PublicGameDetailLoad",
    args: [LoadArg(label: "game_id", type_ref: "Int")],
    save_result_type: None,
  )
}

fn admin_games_load() -> LoadRpc {
  LoadRpc(
    name: "admin_games",
    module_path: "admin/pages/games",
    wire_module: "admin/pages/games",
    import_on_client: False,
    request_constructor: "AdminGamesLoad",
    args: [],
    save_result_type: Some("GameUpdate"),
  )
}

fn loads() -> List(LoadRpc) {
  [admin_games_load(), public_games_load(), public_game_detail_load()]
}

fn push_contract() -> PushContract {
  PushContract(module_path: "broadcasts", type_name: "Event")
}

fn load_context() -> LoadContext {
  LoadContext(module_path: "sqlight", type_name: "Connection")
}

fn generated_files() -> List(GeneratedFile) {
  generate(
    loads(),
    push_contract: Some(push_contract()),
    load_context: Some(load_context()),
  )
}

pub fn load_rpc_generated_files_stay_in_rally_namespace_test() {
  let paths =
    list.map(generated_files(), fn(file: GeneratedFile) {
      let GeneratedFile(path:, content: _) = file
      path
    })

  paths
  |> should.equal([
    "src/generated/rally/client_protocol.gleam",
    "src/generated/rally/server_protocol.gleam",
    "src/generated/rally/client_transport.gleam",
    "src/generated/rally/client_transport_ffi.mjs",
    "src/generated/rally/server.gleam",
    "src/generated/rally/server_ws.gleam",
    "src/generated/rally/server_ssr.gleam",
    "src/generated/rally/hydration.gleam",
    "src/generated/rally/browser.gleam",
    "src/generated/rally/browser_ffi.mjs",
    "src/generated/rally/browser_mount.gleam",
    "src/generated/rally/browser_app.gleam",
    "src/generated/rally/result.gleam",
  ])
  paths
  |> list.any(fn(path) { string.starts_with(path, "src/generated/libero/") })
  |> should.be_false()
}

pub fn load_rpc_browser_runtime_helpers_are_app_neutral_test() {
  content_for("src/generated/rally/browser_ffi.mjs")
  |> string.contains("data-rally-spa-nav")
  |> should.be_true()
  content_for("src/generated/rally/client_transport_ffi.mjs")
  |> string.contains("rally:to-server")
  |> should.be_true()
  content_for("src/generated/rally/client_transport_ffi.mjs")
  |> string.contains("__rallySocket")
  |> should.be_true()

  [
    "src/generated/rally/browser_ffi.mjs",
    "src/generated/rally/browser_mount.gleam",
    "src/generated/rally/client_transport_ffi.mjs",
  ]
  |> list.any(fn(path) { content_for(path) |> string.contains("scoreboard") })
  |> should.be_false()
}

pub fn load_rpc_client_protocol_snapshot_test() {
  content_for("src/generated/rally/client_protocol.gleam")
  |> birdie.snap("load_rpc_client_protocol_gleam")
}

pub fn load_rpc_server_protocol_snapshot_test() {
  content_for("src/generated/rally/server_protocol.gleam")
  |> birdie.snap("load_rpc_server_protocol_gleam")
}

pub fn load_rpc_protocols_use_neutral_libero_codec_test() {
  let client = content_for("src/generated/rally/client_protocol.gleam")
  let server = content_for("src/generated/rally/server_protocol.gleam")

  client
  |> string.contains("import generated/libero/etf as libero_etf")
  |> should.be_true()
  server
  |> string.contains("import generated/libero/etf as libero_etf")
  |> should.be_true()

  client |> string.contains("../libero/codec_ffi.mjs") |> should.be_false()
  server
  |> string.contains("generated/libero/to_client_codec")
  |> should.be_false()
  server
  |> string.contains("generated/libero/to_server_codec")
  |> should.be_false()
  server |> string.contains("to_client_codec_ffi") |> should.be_false()
  server |> string.contains("to_server_codec_ffi") |> should.be_false()
}

pub fn load_rpc_server_protocol_uses_libero_wire_encoders_test() {
  let server = content_for("src/generated/rally/server_protocol.gleam")

  server
  |> string.contains(
    "@external(erlang, \"generated@rpc_wire\", \"encode_public_pages_games_wire__load_result\")",
  )
  |> should.be_true()
  server
  |> string.contains(
    "@external(erlang, \"generated@rpc_wire\", \"encode_admin_pages_games__game_update\")",
  )
  |> should.be_true()
  server
  |> string.contains(
    "@external(erlang, \"generated@rpc_wire\", \"encode_broadcasts__event\")",
  )
  |> should.be_true()
  server
  |> string.contains("encode_public_games_load_result_payload(result)")
  |> should.be_true()
  server
  |> string.contains(
    "let payload = encode_any(#(module, encode_push_payload(message)))",
  )
  |> should.be_true()
}

pub fn load_rpc_derives_libero_type_seeds_test() {
  libero_type_seeds(loads: loads(), push_contract: Some(push_contract()))
  |> should.equal([
    #("broadcasts", "Event"),
    #("admin/pages/games", "ServerMsg"),
    #("admin/pages/games", "LoadResult"),
    #("admin/pages/games", "GameUpdate"),
    #("public/pages/games/wire", "ServerMsg"),
    #("public/pages/games/wire", "LoadResult"),
    #("public/pages/games/id_/wire", "ServerMsg"),
    #("public/pages/games/id_/wire", "LoadResult"),
  ])
}

pub fn load_rpc_can_generate_without_push_contract_test() {
  let files =
    generate(loads(), push_contract: None, load_context: Some(load_context()))
  let client =
    content_for_files(files, "src/generated/rally/client_protocol.gleam")
  let server =
    content_for_files(files, "src/generated/rally/server_protocol.gleam")
  let server_ws =
    content_for_files(files, "src/generated/rally/server_ws.gleam")

  client |> string.contains("import broadcasts") |> should.be_false()
  server |> string.contains("import broadcasts") |> should.be_false()
  server_ws |> string.contains("import broadcasts") |> should.be_false()
  client |> string.contains("UnsupportedPushFrame") |> should.be_true()
  server |> string.contains("encode_push") |> should.be_false()
  server_ws |> string.contains("push_frame") |> should.be_false()

  libero_type_seeds(loads: loads(), push_contract: None)
  |> list.any(fn(seed) { seed == #("broadcasts", "Event") })
  |> should.be_false()
}

pub fn load_rpc_result_module_defines_boundary_errors_test() {
  let source = result_module()

  source
  |> string.contains("pub type ApiLoadError")
  |> should.be_true()
  source
  |> string.contains("pub type ApiSaveError")
  |> should.be_true()
}

pub fn load_rpc_client_transport_snapshot_test() {
  content_for("src/generated/rally/client_transport.gleam")
  |> birdie.snap("load_rpc_client_transport_gleam")
}

pub fn load_rpc_page_server_snapshot_test() {
  content_for("src/generated/rally/server.gleam")
  |> birdie.snap("load_rpc_page_server_gleam")
}

pub fn load_rpc_server_ws_snapshot_test() {
  content_for("src/generated/rally/server_ws.gleam")
  |> birdie.snap("load_rpc_server_ws_gleam")
}

pub fn load_rpc_server_ssr_snapshot_test() {
  content_for("src/generated/rally/server_ssr.gleam")
  |> birdie.snap("load_rpc_server_ssr_gleam")
}

pub fn load_rpc_hydration_snapshot_test() {
  content_for("src/generated/rally/hydration.gleam")
  |> birdie.snap("load_rpc_hydration_gleam")
}

pub fn load_rpc_browser_app_snapshot_test() {
  content_for("src/generated/rally/browser_app.gleam")
  |> birdie.snap("load_rpc_browser_app_gleam")
}

pub fn load_rpc_discover_finds_page_local_wire_loads_test() {
  let root = "./tmp/load_rpc_generator_test"
  let src = root <> "/src"
  let _ = simplifile.delete(file_or_dir_at: root)
  let assert Ok(Nil) =
    simplifile.create_directory_all(src <> "/public/pages/games/id_")
  let assert Ok(Nil) = simplifile.create_directory_all(src <> "/admin/pages")
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/admin/pages/games.gleam",
      "pub type ServerMsg {
  AdminGamesLoad
  AdminGamesUpdateScore(game_id: Int)
}

pub type LoadResult {
  AdminGamesLoaded(games: List(GameSummary))
}

pub type GameUpdate {
  AdminGamesUpdated(game: GameSummary)
}

pub type GameSummary {
  GameSummary(id: Int)
}
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/public/pages/games/wire.gleam",
      "pub type ServerMsg {
  PublicGamesLoad
}

pub type LoadResult {
  PublicGamesLoaded(games: List(GameSummary))
}

pub type GameSummary {
  GameSummary(id: Int)
}
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/public/pages/games/id_/wire.gleam",
      "pub type ServerMsg {
  PublicGameDetailLoad(game_id: Int)
}

pub type LoadResult {
  PublicGameDetailLoaded(id: Int)
}
",
    )

  let assert Ok(discovered) = discover(src)

  let assert Ok(LoadRpc(
    name: "public_games",
    module_path: "public/pages/games",
    wire_module: "public/pages/games/wire",
    import_on_client: True,
    request_constructor: "PublicGamesLoad",
    args: [],
    save_result_type: None,
  )) = list.find(discovered, fn(load) { load.name == "public_games" })

  let assert Ok(LoadRpc(
    name: "public_game_detail",
    module_path: "public/pages/games/id_",
    wire_module: "public/pages/games/id_/wire",
    import_on_client: True,
    request_constructor: "PublicGameDetailLoad",
    args: [LoadArg(label: "game_id", type_ref: "Int")],
    save_result_type: None,
  )) = list.find(discovered, fn(load) { load.name == "public_game_detail" })

  let assert Ok(LoadRpc(
    name: "admin_games",
    module_path: "admin/pages/games",
    wire_module: "admin/pages/games",
    import_on_client: False,
    request_constructor: "AdminGamesLoad",
    args: [],
    save_result_type: Some("GameUpdate"),
  )) = list.find(discovered, fn(load) { load.name == "admin_games" })
}

pub fn load_rpc_discover_rejects_app_owned_wire_payload_types_test() {
  let root = "./tmp/load_rpc_boundary_test"
  let src = root <> "/src"
  let _ = simplifile.delete(file_or_dir_at: root)
  let assert Ok(Nil) =
    simplifile.create_directory_all(src <> "/public/pages/games")
  let assert Ok(Nil) = simplifile.create_directory_all(src <> "/public/helpers")
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/public/helpers/display.gleam",
      "pub type GameRow {
  GameRow(id: Int)
}
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/public/pages/games/wire.gleam",
      "import public/helpers/display

pub type ServerMsg {
  PublicGamesLoad
}

pub type LoadResult {
  PublicGamesLoaded(rows: List(display.GameRow))
}
",
    )

  let assert Error(message) = discover(src)

  message
  |> string.contains(
    "Invalid wire boundary in public/pages/games/wire.LoadResult",
  )
  |> should.be_true()
  message
  |> string.contains("LoadResult.PublicGamesLoaded.rows")
  |> should.be_true()
  message
  |> string.contains("public/helpers/display.GameRow")
  |> should.be_true()
}

pub fn load_rpc_discover_rejects_transitive_wire_payload_leaks_test() {
  let root = "./tmp/load_rpc_boundary_transitive_test"
  let src = root <> "/src"
  let _ = simplifile.delete(file_or_dir_at: root)
  let assert Ok(Nil) =
    simplifile.create_directory_all(src <> "/public/pages/games")
  let assert Ok(Nil) = simplifile.create_directory_all(src <> "/public/helpers")
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/public/helpers/display.gleam",
      "pub type GameRow {
  GameRow(id: Int)
}
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/public/pages/games/wire.gleam",
      "import public/helpers/display

pub type ServerMsg {
  PublicGamesLoad
}

pub type LoadResult {
  PublicGamesLoaded(games: List(GameSummary))
}

pub type GameSummary {
  GameSummary(row: display.GameRow)
}
",
    )

  let assert Error(message) = discover(src)

  message
  |> string.contains(
    "Invalid wire boundary in public/pages/games/wire.LoadResult",
  )
  |> should.be_true()
  message
  |> string.contains(
    "LoadResult.PublicGamesLoaded.games -> public/pages/games/wire.GameSummary.GameSummary.row",
  )
  |> should.be_true()
  message
  |> string.contains("public/helpers/display.GameRow")
  |> should.be_true()
}

pub fn load_rpc_discover_rejects_query_row_wire_payload_types_test() {
  let root = "./tmp/load_rpc_boundary_query_row_test"
  let src = root <> "/src"
  let _ = simplifile.delete(file_or_dir_at: root)
  let assert Ok(Nil) =
    simplifile.create_directory_all(src <> "/public/pages/games")
  let assert Ok(Nil) = simplifile.create_directory_all(src <> "/generated/sql")
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/generated/sql/games_sql.gleam",
      "pub type Row {
  Row(id: Int)
}
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/public/pages/games/wire.gleam",
      "import generated/sql/games_sql

pub type ServerMsg {
  PublicGamesLoad
}

pub type LoadResult {
  PublicGamesLoaded(row: games_sql.Row)
}
",
    )

  let assert Error(message) = discover(src)

  message
  |> string.contains(
    "Invalid wire boundary in public/pages/games/wire.LoadResult",
  )
  |> should.be_true()
  message
  |> string.contains("LoadResult.PublicGamesLoaded.row")
  |> should.be_true()
  message
  |> string.contains("generated/sql/games_sql.Row")
  |> should.be_true()
}

pub fn load_rpc_discover_rejects_targeted_wire_imports_test() {
  let root = "./tmp/load_rpc_boundary_targeted_import_test"
  let src = root <> "/src"
  let _ = simplifile.delete(file_or_dir_at: root)
  let assert Ok(Nil) =
    simplifile.create_directory_all(src <> "/public/pages/games")
  let assert Ok(Nil) = simplifile.create_directory_all(src <> "/wire")
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/wire/game.gleam",
      "pub type GameSummary {
  GameSummary(id: Int)
}
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/public/pages/games/wire.gleam",
      "@target(erlang)
import wire/game

pub type ServerMsg {
  PublicGamesLoad
}

pub type LoadResult {
  PublicGamesLoaded(game: game.GameSummary)
}
",
    )

  let assert Error(message) = discover(src)

  message
  |> string.contains(
    "Invalid wire import in public/pages/games/wire.LoadResult",
  )
  |> should.be_true()
  message
  |> string.contains("LoadResult.PublicGamesLoaded.game")
  |> should.be_true()
  message
  |> string.contains("wire/game.GameSummary")
  |> should.be_true()
  message
  |> string.contains("@target(erlang) import wire/game")
  |> should.be_true()
}

pub fn load_rpc_discover_allows_shared_wire_payload_types_test() {
  let root = "./tmp/load_rpc_boundary_valid_test"
  let src = root <> "/src"
  let _ = simplifile.delete(file_or_dir_at: root)
  let assert Ok(Nil) =
    simplifile.create_directory_all(src <> "/public/pages/games")
  let assert Ok(Nil) = simplifile.create_directory_all(src <> "/wire")
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/wire/game.gleam",
      "pub type GameSummary {
  GameSummary(id: Int)
}
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/public/pages/games/wire.gleam",
      "import wire/game

pub type ServerMsg {
  PublicGamesLoad
}

pub type LoadResult {
  PublicGamesLoaded(games: List(game.GameSummary))
}
",
    )

  let assert Ok(discovered) = discover(src)

  let assert Ok(LoadRpc(
    name: "public_games",
    module_path: "public/pages/games",
    wire_module: "public/pages/games/wire",
    import_on_client: True,
    request_constructor: "PublicGamesLoad",
    args: [],
    save_result_type: None,
  )) = list.find(discovered, fn(load) { load.name == "public_games" })
}

fn content_for(path: String) -> String {
  content_for_files(generated_files(), path)
}

fn content_for_files(files: List(GeneratedFile), path: String) -> String {
  let assert Ok(GeneratedFile(content:, ..)) =
    list.find(files, fn(file) {
      let GeneratedFile(path: file_path, ..) = file
      file_path == path
    })
  format.format_gleam(content)
}
