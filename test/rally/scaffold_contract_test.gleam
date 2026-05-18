import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import libero/codegen_dispatch
import rally/internal/generator
import rally/internal/generator/client
import rally/internal/generator/ssr_handler
import rally/internal/generator/ws_handler
import rally/internal/init
import rally/internal/types.{
  type ScanConfig, DynamicSegment, PageContract, ScanConfig, ScannedRoute,
  StaticSegment, StringParam,
}
import simplifile
import tom

fn scaffold_source() -> String {
  init.files("my_app")
  |> list.map(fn(file) { file.path <> "\n" <> file.contents })
  |> string.join("\n")
}

pub fn empty_rpc_dispatch_handles_bad_variant_tags_test() {
  let output = generator.generate_empty_rpc_dispatch("generated@rpc_atoms", [])

  output
  |> string.contains("Error(_) ->")
  |> should.equal(True)

  output
  |> string.contains("UnknownFunction(\"rpc\")")
  |> should.equal(True)
}

pub fn empty_rpc_dispatch_with_identity_extra_param_test() {
  let output =
    generator.generate_empty_rpc_dispatch("generated@rpc_atoms", [
      codegen_dispatch.ExtraParam(
        name: "identity",
        type_ref: "auth.Identity",
        import_line: "import admin/auth",
      ),
    ])

  // Must import the auth module
  output
  |> string.contains("import admin/auth")
  |> should.equal(True)
  // Must include identity in the handle signature
  output
  |> string.contains("identity _identity: auth.Identity")
  |> should.equal(True)
}

pub fn rpc_dispatch_context_import_is_local_test() {
  let output =
    generator.normalize_rpc_dispatch_context_import(
      "import server/server_context.{type ServerContext}\n",
    )

  output
  |> should.equal("import server_context.{type ServerContext}\n")
}

pub fn rpc_dispatch_unused_fields_are_underscored_test() {
  let output =
    generator.normalize_rpc_dispatch_unused_fields(
      "            ServerLogin(email:, password:) -> {\n              Nil\n            }\n            ServerLogout -> {\n              Nil\n            }\n",
    )

  output
  |> string.contains("ServerLogin(email: _, password: _) -> {")
  |> should.equal(True)

  output
  |> string.contains("ServerLogin(email:, password:) -> {")
  |> should.equal(False)

  output
  |> string.contains("ServerLogout -> {")
  |> should.equal(True)
}

pub fn scaffold_uses_app_env_and_no_client_context_page_arity_test() {
  let script = scaffold_source()

  script
  |> string.contains("src/my_app.gleam")
  |> should.equal(True)

  script
  |> string.contains("APP_ENV=dev")
  |> should.equal(True)

  script
  |> string.contains("import rally_runtime/env")
  |> should.equal(True)

  script
  |> string.contains(
    "session.set_cookie_header(session_id:, secure: env.secure_cookies())",
  )
  |> should.equal(True)

  script
  |> string.contains(
    "import server_context.{type ServerContext, ServerContext}",
  )
  |> should.equal(True)

  script
  |> string.contains("ssr_handler.handle_request(")
  |> should.equal(True)

  script
  |> string.contains("server_context: server_context")
  |> should.equal(True)

  script
  |> string.contains("{{rally_client_script}}")
  |> should.equal(True)

  script
  |> string.contains("/_build/client/generated/app.mjs")
  |> should.equal(False)

  script
  |> string.contains("const client_build_root")
  |> should.equal(True)

  script
  |> string.contains("case string.starts_with(path, \"/_build/\")")
  |> should.equal(True)

  script
  |> string.contains(
    "|> response.set_header(\"content-type\", content_type(path))",
  )
  |> should.equal(True)

  script
  |> string.contains("gleam run -m app")
  |> should.equal(False)

  script
  |> string.contains("gleam run\n")
  |> should.equal(False)

  script
  |> string.contains("pub fn load(server_context: ServerContext) -> Model")
  |> should.equal(True)

  script
  |> string.contains("pub fn update(model: Model, msg: Msg)")
  |> should.equal(True)

  script
  |> string.contains("pub fn view(model: Model)")
  |> should.equal(True)

  script
  |> string.contains("counter_sql.increment(db: server_context.db)")
  |> should.equal(True)

  script
  |> string.contains("counter_sql.decrement(db: server_context.db)")
  |> should.equal(True)

  script
  |> string.contains("import rally_runtime/migrate")
  |> should.equal(False)

  script
  |> string.contains("migrate.run")
  |> should.equal(False)
}

pub fn scaffold_uses_namespaced_client_config_test() {
  let script = scaffold_source()

  script
  |> string.contains("[[tools.rally.clients]]")
  |> should.equal(True)

  script
  |> string.contains("namespace = \"public\"")
  |> should.equal(True)

  script
  |> string.contains("route_root = \"/\"")
  |> should.equal(True)

  script
  |> string.contains("src/public/pages")
  |> should.equal(True)

  script
  |> string.contains(".generated_clients/public")
  |> should.equal(True)
}

pub fn scaffold_routes_http_rpc_test() {
  let script = scaffold_source()

  script
  |> string.contains("import generated/public/http_handler as http_handler")
  |> should.equal(True)

  script
  |> string.contains("\"/rpc\" ->")
  |> should.equal(True)

  script
  |> string.contains("mist.read_body(req, max_body_limit: 16_000_000)")
  |> should.equal(True)

  script
  |> string.contains("http_handler.handle(")
  |> should.equal(True)

  script
  |> string.contains("server_context: server_context")
  |> should.equal(True)

  script
  |> string.contains("session_id: session_id")
  |> should.equal(True)
}

pub fn realworld_routes_http_rpc_test() {
  let assert Ok(source) =
    simplifile.read("examples/realworld/src/realworld.gleam")

  source
  |> string.contains("import generated/public/http_handler")
  |> should.equal(True)

  source
  |> string.contains("\"/rpc\" ->")
  |> should.equal(True)

  source
  |> string.contains("mist.read_body(req, max_body_limit: 16_000_000)")
  |> should.equal(True)

  source
  |> string.contains("http_handler.handle")
  |> should.equal(True)
}

pub fn ws_handler_logs_decoded_rpc_value_test() {
  let output =
    ws_handler.generate(
      [],
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      option.None,
      from_session_module: "client_context_server",
      endpoints: [],
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  output
  |> string.contains("system_db.log_to_server(")
  |> should.equal(True)

  output
  |> string.contains("variant_name: wire.rpc_identity(envelope),")
  |> should.equal(True)

  output
  |> string.contains("raw_payload: wire.rpc_raw_payload(envelope),")
  |> should.equal(True)

  output
  |> string.contains("dynamic.nil()")
  |> should.equal(False)
}

pub fn ws_handler_wires_stateful_page_effects_test() {
  let route =
    ScannedRoute(
      segments: [StaticSegment("article"), DynamicSegment("slug", StringParam)],
      variant_name: "ArticleSlug",
      params: [#("slug", StringParam)],
      layout_module: None,
      module_path: "public/pages/article/slug_",
    )
  let contract =
    PageContract(
      model_variants: [],
      msg_variants: [],
      has_load: False,
      has_init: True,
      has_init_loaded: False,
      has_server_init: True,
      has_server_update: True,
      has_model: True,
      updates_client_context: False,
      param_names: ["slug"],
      source: "pub fn server_init(\n  server_context: ServerContext,\n  slug: String,\n) { todo }\n\npub fn server_update(\n  model: ServerModel,\n  msg: ToServer,\n  server_context: ServerContext,\n) { todo }\n",
      view_source: "",
      init_source: "",
      update_source: "",
      has_page_auth: False,
      page_auth_required: False,
      has_authorize: False,
    )
  let output =
    ws_handler.generate(
      [#(route, contract)],
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      option.None,
      from_session_module: "server_context",
      endpoints: [],
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  output
  |> string.contains("import rally_runtime/internal/effect_runner")
  |> should.equal(True)

  output
  |> string.contains("let Nil = run_server_init(page, value, server_context)")
  |> should.equal(True)

  output
  |> string.contains(
    "public_pages_article_slug_.server_init(server_context, param_0)",
  )
  |> should.equal(True)

  output
  |> string.contains("let Nil = effect_state.put_ws_server_model(server_model)")
  |> should.equal(True)

  output
  |> string.contains("effect_runner.perform(server_effect)")
  |> should.equal(True)

  output
  |> string.contains("public_pages_article_slug_.server_update(")
  |> should.equal(True)
}

pub fn codegen_resets_generated_client_src_test() {
  let assert Ok(source) = simplifile.read("src/rally.gleam")

  source
  |> string.contains("reset_generated_client_src(config.client_root)")
  |> should.equal(True)

  source
  |> string.contains("simplifile.delete_all(paths: [client_root <> \"/src\"])")
  |> should.equal(True)
}

pub fn client_package_keeps_absolute_dependency_paths_test() {
  let deps =
    dict.from_list([
      #(
        "shared_widgets",
        tom.InlineTable(
          dict.from_list([#("path", tom.String("/tmp/shared_widgets"))]),
        ),
      ),
    ])
  let mock_files = [
    client.GeneratedFile(
      ".generated_clients/src/pages/home.gleam",
      "import shared/widgets/button\npub type Model { Model }\n",
    ),
  ]
  let file =
    client.generate_gleam_toml(
      all_client_files: mock_files,
      server_deps: deps,
      client_root: ".generated_clients",
      protocol: "etf",
    )

  file.content
  |> string.contains("shared_widgets = { path = \"/tmp/shared_widgets\" }")
  |> should.equal(True)
}

pub fn client_package_does_not_copy_server_runtime_deps_test() {
  let deps =
    dict.from_list([
      #("mist", tom.String(">= 6.0.0 and < 7.0.0")),
      #("sqlight", tom.String(">= 1.0.0 and < 2.0.0")),
      #(
        "libero",
        tom.InlineTable(dict.from_list([#("path", tom.String("/tmp/libero"))])),
      ),
    ])
  let mock_files = [
    client.GeneratedFile(
      ".generated_clients/src/generated/codec.gleam",
      "import libero/codec\npub fn decode() { Nil }\n",
    ),
  ]
  let file =
    client.generate_gleam_toml(
      all_client_files: mock_files,
      server_deps: deps,
      client_root: ".generated_clients",
      protocol: "etf",
    )

  file.content
  |> string.contains("mist")
  |> should.equal(False)

  file.content
  |> string.contains("sqlight")
  |> should.equal(False)

  file.content
  |> string.contains("libero")
  |> should.equal(True)
}

pub fn json_client_package_uses_hex_libero_test() {
  let config = ScanConfig(..test_scan_config(), protocol: "json")
  let files = client.generate_package([], [], config, "", False)
  let file =
    client.generate_gleam_toml(
      all_client_files: files,
      server_deps: dict.new(),
      client_root: config.client_root,
      protocol: "json",
    )

  file.content
  |> string.contains("libero = \">= 6.0.0 and < 7.0.0\"")
  |> should.equal(True)

  file.content
  |> string.contains("libero = { path")
  |> should.equal(False)
}

pub fn ssr_omits_layout_import_when_no_load_arm_uses_it_test() {
  let route =
    ScannedRoute(
      segments: [StaticSegment("home")],
      variant_name: "Home",
      params: [],
      layout_module: Some("pages/layout"),
      module_path: "pages/home_",
    )
  let contract =
    PageContract(
      model_variants: [],
      msg_variants: [],
      has_load: False,
      has_init: True,
      has_init_loaded: False,
      has_server_init: False,
      has_server_update: False,
      has_model: True,
      updates_client_context: False,
      param_names: [],
      source: "",
      view_source: "",
      init_source: "",
      update_source: "",
      has_page_auth: False,
      page_auth_required: False,
      has_authorize: False,
    )
  let output =
    ssr_handler.generate(
      [#(route, contract)],
      False,
      False,
      "server_context",
      "generated/router",
      "<html><head></head><body><div id=\"app\"></div></body></html>",
      "generated/public/rpc_atoms",
      option.None,
      option.None,
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  output
  |> string.contains("import pages/layout")
  |> should.equal(False)
}

pub fn run_does_not_swallow_generated_file_write_errors_test() {
  let assert Ok(source) = simplifile.read("src/rally.gleam")

  source
  |> string.contains("let _ = write_file(config.output_http, http_source)")
  |> should.equal(False)

  source
  |> string.contains("let _ = simplifile.create_directory_all(dirname(path))")
  |> should.equal(False)
}

pub fn ssr_missing_app_marker_falls_back_to_shell_test() {
  let output =
    ssr_handler.generate(
      [
        #(
          ScannedRoute(
            segments: [StaticSegment("home")],
            variant_name: "Home",
            params: [],
            layout_module: None,
            module_path: "pages/home_",
          ),
          PageContract(
            model_variants: [],
            msg_variants: [],
            has_load: True,
            has_init: True,
            has_init_loaded: False,
            has_server_init: False,
            has_server_update: False,
            has_model: True,
            updates_client_context: False,
            param_names: [],
            source: "",
            view_source: "",
            init_source: "",
            update_source: "",
            has_page_auth: False,
            page_auth_required: False,
            has_authorize: False,
          ),
        ),
      ],
      False,
      False,
      "server_context",
      "generated/router",
      "<html><head></head><body><main></main></body></html>",
      "generated/public/rpc_atoms",
      option.None,
      option.None,
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  output
  |> string.contains("Error(Nil) -> shell")
  |> should.equal(True)
}

pub fn ssr_app_marker_preserves_tag_order_test() {
  let output =
    ssr_handler.generate(
      [
        #(
          ScannedRoute(
            segments: [StaticSegment("home")],
            variant_name: "Home",
            params: [],
            layout_module: None,
            module_path: "pages/home_",
          ),
          PageContract(
            model_variants: [],
            msg_variants: [],
            has_load: True,
            has_init: True,
            has_init_loaded: False,
            has_server_init: False,
            has_server_update: False,
            has_model: True,
            updates_client_context: False,
            param_names: [],
            source: "",
            view_source: "",
            init_source: "",
            update_source: "",
            has_page_auth: False,
            page_auth_required: False,
            has_authorize: False,
          ),
        ),
      ],
      False,
      False,
      "server_context",
      "generated/router",
      "<html><head></head><body><main class=\"root\" id = \"app\"></main></body></html>",
      "generated/public/rpc_atoms",
      option.None,
      option.None,
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  output
  |> string.contains("let tag_start = \"<\" <> string.reverse(after_lt_rev)")
  |> should.equal(True)

  output
  |> string.contains("let id_dq_spaced = \"id = \\\"app\\\"\"")
  |> should.equal(True)
}

pub fn ssr_replaces_client_script_marker_test() {
  let output =
    ssr_shell_output(
      "<html><head></head><body><div id=\"app\"></div>{{rally_client_script}}</body></html>",
    )

  output
  |> string.contains("{{rally_client_script}}")
  |> should.equal(False)

  output
  |> string.contains("/_build/client/generated/app.mjs")
  |> should.equal(True)
}

pub fn ssr_injects_client_script_when_shell_omits_marker_test() {
  let output =
    ssr_shell_output(
      "<html><head></head><body><div id=\"app\"></div></body></html>",
    )

  output
  |> string.contains("/_build/client/generated/app.mjs")
  |> should.equal(True)
}

pub fn ssr_rewrites_stale_generated_app_path_test() {
  let output =
    ssr_shell_output(
      "<html><head></head><body><div id=\"app\"></div><script type='module'>import { main } from '/_build/public/generated/app.mjs'; main();</script></body></html>",
    )

  output
  |> string.contains("/_build/public/generated/app.mjs")
  |> should.equal(False)

  output
  |> string.contains("/_build/client/generated/app.mjs")
  |> should.equal(True)
}

fn ssr_shell_output(shell_html: String) -> String {
  ssr_handler.generate(
    [],
    False,
    False,
    "server_context",
    "generated/router",
    shell_html,
    "generated/public/rpc_atoms",
    option.None,
    option.None,
    option.None,
    wire_import_module: "generated/public/protocol_wire",
    protocol: "etf",
  )
}

fn test_scan_config() -> ScanConfig {
  ScanConfig(
    pages_root: "src/pages",
    output_route: "",
    output_dispatch: "",
    output_server_dispatch: "",
    output_server_atoms: "",
    atoms_module: "",
    output_server_wire: "",
    wire_module: "",
    output_ssr: "",
    output_ws: "",
    output_http: "",
    client_root: ".generated_clients",
    route_root: "/",
    rally_package_path: "",
    shell_file: "",
    server_deps: dict.new(),
    protocol: "etf",
  )
}
