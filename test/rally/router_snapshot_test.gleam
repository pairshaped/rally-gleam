//// Snapshot tests for generated router, dispatch, SSR, client app, and codecs.
////
//// These tests protect the public shape of generated source files. Use this
//// file when a generator change should alter emitted code intentionally, then
//// review the Birdie snapshots as the readable diff of Rally's output.

import birdie
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import libero/field_type.{BoolField, IntField, StringField, UserType}
import libero/scanner
import rally/internal/generator
import rally/internal/generator/client
import rally/internal/generator/codec
import rally/internal/generator/ssr_handler
import rally/internal/types.{
  type ClientContextContract, type PageContract, type ScanConfig,
  type ScannedRoute, ClientContextContract, DynamicSegment, IntParam,
  PageContract, ScanConfig, ScannedRoute, StaticSegment, StringParam,
  VariantField, VariantInfo,
}

fn basic_routes() -> List(ScannedRoute) {
  [
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: None,
      module_path: "pages/home_",
    ),
    ScannedRoute(
      segments: [StaticSegment("about")],
      variant_name: "About",
      params: [],
      layout_module: None,
      module_path: "pages/about",
    ),
    ScannedRoute(
      segments: [StaticSegment("users"), DynamicSegment("id", IntParam)],
      variant_name: "UsersId",
      params: [#("id", IntParam)],
      layout_module: None,
      module_path: "pages/users/id_",
    ),
  ]
}

fn basic_contracts() -> List(#(ScannedRoute, PageContract)) {
  let routes = basic_routes()
  list.map(routes, fn(route) {
    #(
      route,
      PageContract(
        model_variants: [
          VariantInfo("Model", [VariantField("count", IntField)]),
        ],
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
        has_fallible_init: False,
      ),
    )
  })
}

fn client_context_contract_with_browser_fields() -> ClientContextContract {
  ClientContextContract(
    context_variants: [
      VariantInfo("ClientContext", [
        VariantField("current_path", StringField),
        VariantField("dark_mode", BoolField),
        VariantField("lang", StringField),
      ]),
    ],
    msg_variants: [VariantInfo("NoOp", [])],
    has_init: True,
    has_update: True,
  )
}

pub fn router_output_snapshot_test() {
  let routes = basic_routes()
  let output = generator.generate(routes)
  birdie.snap(output, "route_gleam")
}

pub fn router_uses_qualified_percent_encode_without_value_import_test() {
  let route =
    ScannedRoute(
      segments: [StaticSegment("articles"), DynamicSegment("slug", StringParam)],
      variant_name: "ArticleSlug",
      params: [#("slug", StringParam)],
      layout_module: None,
      module_path: "pages/articles/slug_",
    )
  let output = generator.generate([route])

  output
  |> string.contains("import gleam/uri.{type Uri, percent_encode}")
  |> should.equal(False)

  output
  |> string.contains("uri.percent_encode(slug)")
  |> should.equal(True)
}

pub fn dispatch_output_snapshot_test() {
  let routes = basic_routes()
  let output =
    generator.generate_dispatch(
      routes,
      basic_contracts(),
      False,
      "generated/router",
      "client_context",
    )
  birdie.snap(output, "page_dispatch_gleam")
}

pub fn app_gleam_uses_nearest_layout_per_page_test() {
  let home =
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: Some("pages/layout"),
      module_path: "pages/home_",
    )
  let settings =
    ScannedRoute(
      segments: [StaticSegment("settings"), StaticSegment("profile")],
      variant_name: "SettingsProfile",
      params: [],
      layout_module: Some("pages/settings/layout"),
      module_path: "pages/settings/profile",
    )
  let routes = [home, settings]
  let contracts =
    list.map(routes, fn(route) {
      #(
        route,
        PageContract(
          model_variants: [
            VariantInfo("Model", [VariantField("count", IntField)]),
          ],
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
          has_fallible_init: False,
        ),
      )
    })
  let files =
    client.generate_package(routes, contracts, test_scan_config(), "", True)
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })

  file.content
  |> string.contains("import pages/layout as pages_layout")
  |> should.equal(True)

  file.content
  |> string.contains("import pages/settings/layout as pages_settings_layout")
  |> should.equal(True)

  file.content
  |> string.contains("HomePageModel(_) ->\n      pages_layout.layout")
  |> should.equal(True)

  file.content
  |> string.contains(
    "SettingsProfilePageModel(_) ->\n      pages_settings_layout.layout",
  )
  |> should.equal(True)
}

pub fn ssr_handler_snapshot_test() {
  let contracts = basic_contracts()
  let shell =
    "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'></head>\n<body><div id='app'></div><script type='module' src='/_build/client/generated/app.mjs'></script></body>\n</html>"
  let output =
    ssr_handler.generate(
      contracts,
      False,
      False,
      "server_context",
      "generated/router",
      shell,
      "generated/public/rpc_atoms",
      option.None,
      option.None,
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )
  birdie.snap(output, "ssr_handler_gleam")
}

pub fn ssr_handler_sets_content_type_for_load_pages_test() {
  let contracts = basic_contracts()
  let shell =
    "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'></head>\n<body><div id='app'></div><script type='module' src='/_build/client/generated/app.mjs'></script></body>\n</html>"
  let output =
    ssr_handler.generate(
      contracts,
      False,
      False,
      "server_context",
      "generated/router",
      shell,
      "generated/public/rpc_atoms",
      option.None,
      option.None,
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )
  let content_type_count =
    output
    |> string.split("|> response.set_header(\"content-type\", \"text/html\")")
    |> list.length
    |> fn(count) { count - 1 }

  content_type_count |> should.equal(3)
}

pub fn ssr_handler_with_client_context_snapshot_test() {
  let contracts = basic_contracts()
  let shell =
    "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'></head>\n<body><div id='app'></div><script type='module' src='/_build/client/generated/app.mjs'></script></body>\n</html>"
  let output =
    ssr_handler.generate(
      contracts,
      True,
      True,
      "server_context",
      "generated/router",
      shell,
      "generated/public/rpc_atoms",
      option.None,
      option.None,
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )
  birdie.snap(output, "ssr_handler_with_client_context_gleam")
}

pub fn ssr_handler_uses_protocol_wire_flags_without_etf_wrappers_test() {
  let contracts = basic_contracts()
  let shell =
    "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'></head>\n<body><div id='app'></div><script type='module' src='/_build/client/generated/app.mjs'></script></body>\n</html>"
  let output =
    ssr_handler.generate(
      contracts,
      True,
      True,
      "server_context",
      "generated/router",
      shell,
      "generated/public/rpc_atoms",
      Some("generated@rpc_wire"),
      Some("public/client_context"),
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  output
  |> string.contains("let flags = libero_wire.encode_flags(model)")
  |> should.equal(True)

  output
  |> string.contains("let encoded = libero_wire.encode_flags(client_context)")
  |> should.equal(True)

  output
  |> string.contains("wire_encode_")
  |> should.equal(False)

  output
  |> string.contains("@external(erlang, \"generated@rpc_wire\"")
  |> should.equal(False)
}

pub fn ssr_shell_handler_marks_unused_route_test() {
  let route =
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: None,
      module_path: "pages/home_",
    )
  let contract =
    PageContract(
      model_variants: [
        VariantInfo("Model", [VariantField("count", IntField)]),
      ],
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
      has_fallible_init: False,
    )
  let shell =
    "<!DOCTYPE html>\n<html><head></head><body><div id='app'></div></body></html>"
  let output =
    ssr_handler.generate(
      [#(route, contract)],
      True,
      True,
      "server_context",
      "generated/router",
      shell,
      "generated/public/rpc_atoms",
      option.None,
      Some("public/client_context"),
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  output
  |> string.contains("route _route: router.Route")
  |> should.equal(True)

  output
  |> string.contains("route route: router.Route")
  |> should.equal(False)
}

pub fn app_gleam_with_client_context_snapshot_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let config = test_scan_config()
  let files = client.generate_package(routes, contracts, config, "", True)
  let app =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })
  let assert Ok(file) = app
  birdie.snap(file.content, "client_app_with_client_context_gleam")
}

pub fn app_gleam_with_browser_client_context_snapshot_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let config = test_scan_config()
  let files =
    client.generate_package_with_client_context_contract(
      routes,
      contracts,
      config,
      "",
      Some(client_context_contract_with_browser_fields()),
      "client_context",
      "etf",
    )
  let app =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })
  let assert Ok(file) = app
  birdie.snap(file.content, "client_app_with_browser_client_context_gleam")
}

pub fn client_app_syncs_browser_client_context_fields_test() {
  let files =
    client.generate_package_with_client_context_contract(
      basic_routes(),
      basic_contracts(),
      test_scan_config(),
      "",
      Some(client_context_contract_with_browser_fields()),
      "client_context",
      "etf",
    )
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })

  file.content
  |> string.contains("import rally/runtime/effect as rally_effect")
  |> should.equal(True)

  file.content
  |> string.contains("let client_context = client_context.ClientContext(")
  |> should.equal(True)

  file.content
  |> string.contains("..client_context")
  |> should.equal(True)

  file.content
  |> string.contains("current_path: current_path")
  |> should.equal(True)

  file.content
  |> string.contains("dark_mode: rally_effect.read_dark_mode()")
  |> should.equal(True)

  file.content
  |> string.contains("lang: rally_effect.read_lang()")
  |> should.equal(True)

  file.content
  |> string.contains("let new_client_context =")
  |> should.equal(True)

  file.content
  |> string.contains(
    "client_context.ClientContext(..model.client_context, current_path:)",
  )
  |> should.equal(True)

  file.content
  |> string.contains(
    "init_page(route: route, client_context: new_client_context)",
  )
  |> should.equal(True)

  file.content
  |> string.contains("client_context: new_client_context")
  |> should.equal(True)
}

pub fn client_app_omits_unused_effect_import_and_record_updates_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let files =
    client.generate_package(routes, contracts, test_scan_config(), "", True)
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })

  file.content
  |> string.contains("import rally/runtime/effect as rally_effect")
  |> should.equal(False)

  file.content
  |> string.contains("client_context.ClientContext(..ctx)")
  |> should.equal(False)

  file.content
  |> string.contains("client_context.ClientContext(..ctx_model)")
  |> should.equal(False)
}

pub fn client_app_underscores_ignored_hydrate_route_params_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let files =
    client.generate_package(routes, contracts, test_scan_config(), "", False)
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })

  file.content
  |> string.contains("router.UsersId(_id) -> {")
  |> should.equal(True)

  file.content
  |> string.contains("UsersIdPageModel(model)")
  |> should.equal(True)
}

pub fn client_app_uses_hydrate_context_for_fallback_init_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let files =
    client.generate_package(routes, contracts, test_scan_config(), "", True)
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })

  file.content
  |> string.contains("client_context: client_context.ClientContext")
  |> should.equal(True)

  file.content
  |> string.contains(
    "Error(_) -> init_page(route: route, client_context: client_context)",
  )
  |> should.equal(True)
}

pub fn client_app_uses_hydrate_context_when_init_loaded_needs_it_test() {
  let route =
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: None,
      module_path: "pages/home_",
    )
  let contract =
    PageContract(
      model_variants: [
        VariantInfo("Model", [VariantField("count", IntField)]),
      ],
      msg_variants: [],
      has_load: True,
      has_init: True,
      has_init_loaded: True,
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
      has_fallible_init: False,
    )
  let files =
    client.generate_package(
      [route],
      [#(route, contract)],
      test_scan_config(),
      "",
      True,
    )
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })

  file.content
  |> string.contains(
    "fn hydrate_page(route: router.Route, flags: String, client_context: client_context.ClientContext)",
  )
  |> should.equal(True)

  file.content
  |> string.contains(
    "codec.decode_flags_typed(flags, \"decode_pages_home__model\")",
  )
  |> should.equal(True)

  file.content
  |> string.contains("transport.apply_typed_decoder")
  |> should.equal(False)

  file.content
  |> string.contains("init_loaded(_client_context")
  |> should.equal(False)
}

pub fn app_gleam_layout_with_client_context_uses_context_msg_mapper_test() {
  let routes = [
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: Some("pages/layout"),
      module_path: "pages/home_",
    ),
  ]
  let contracts =
    list.map(routes, fn(route) {
      #(
        route,
        PageContract(
          model_variants: [
            VariantInfo("Model", [VariantField("count", IntField)]),
          ],
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
          has_fallible_init: False,
        ),
      )
    })
  let files =
    client.generate_package(routes, contracts, test_scan_config(), "", True)
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })

  file.content
  |> string.contains(
    "pages_layout.layout(model.client_context, ClientContextUpdate, content)",
  )
  |> should.equal(True)

  file.content
  |> string.contains("layout.layout(model.client_context,\n    html.div")
  |> should.equal(False)
}

pub fn ssr_layout_with_client_context_uses_v3_session_contract_test() {
  let route =
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: Some("pages/layout"),
      module_path: "pages/home_",
    )
  let contract =
    PageContract(
      model_variants: [VariantInfo("Model", [VariantField("count", IntField)])],
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
      has_fallible_init: False,
    )
  let shell =
    "<!DOCTYPE html>\n<html><head></head><body><div id='app'></div></body></html>"
  let output =
    ssr_handler.generate(
      [#(route, contract)],
      True,
      True,
      "server_context",
      "generated/router",
      shell,
      "generated/public/rpc_atoms",
      option.None,
      Some("public/client_context"),
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  output
  |> string.contains(
    "server_context.from_session(server_context: server_context, session_id: session_id, hostname: hostname)",
  )
  |> should.equal(True)

  output
  |> string.contains(
    "let client_context = server_context.from_session(server_context, session_id)",
  )
  |> should.equal(False)

  output
  |> string.contains("hostname: String")
  |> should.equal(True)

  output
  |> string.contains(
    "fn context_script(client_context: client_context.ClientContext) -> String",
  )
  |> should.equal(True)

  output
  |> string.contains("context_script(server_context, session_id, hostname)")
  |> should.equal(False)
}

pub fn ssr_client_context_without_from_session_imports_client_context_test() {
  let route =
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: None,
      module_path: "pages/home_",
    )
  let contract =
    PageContract(
      model_variants: [VariantInfo("Model", [VariantField("count", IntField)])],
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
      has_fallible_init: False,
    )
  let shell =
    "<!DOCTYPE html>\n<html><head></head><body><div id='app'></div></body></html>"
  let output =
    ssr_handler.generate(
      [#(route, contract)],
      True,
      False,
      "server_context",
      "generated/router",
      shell,
      "generated/public/rpc_atoms",
      option.None,
      Some("public/client_context"),
      option.None,
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  output
  |> string.contains("import public/client_context")
  |> should.equal(True)

  output
  |> string.contains("client_context.init()")
  |> should.equal(True)
}

pub fn transport_gleam_snapshot_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let config = test_scan_config()
  let files = client.generate_package(routes, contracts, config, "", False)
  let transport =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "transport.gleam")
    })
  let assert Ok(file) = transport
  birdie.snap(file.content, "client_transport_gleam")
}

pub fn transport_gleam_exposes_safe_decode_test() {
  let files =
    client.generate_package(
      basic_routes(),
      basic_contracts(),
      test_scan_config(),
      "",
      False,
    )
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "transport.gleam")
    })

  file.content
  |> string.contains("pub type DecodeError")
  |> should.equal(True)
  // Boundary: generated transport must NOT expose raw ETF codec helpers.
  // Consumers use Libero's boundary API (decode_server_frame,
  // decode_flags_typed, encode_request) instead.
  file.content
  |> string.contains("decode_value")
  |> should.equal(False)
  file.content
  |> string.contains("decode_safe")
  |> should.equal(False)
  file.content
  |> string.contains("decode_safe_raw")
  |> should.equal(False)
  file.content
  |> string.contains("apply_typed_decoder")
  |> should.equal(False)
  file.content
  |> string.contains("decodeTyped")
  |> should.equal(False)
  file.content
  |> string.contains("pub fn encode(value: a) -> BitArray")
  |> should.equal(False)
}

pub fn app_gleam_sends_page_init_for_static_routes_test() {
  let files =
    client.generate_package(
      basic_routes(),
      basic_contracts(),
      test_scan_config(),
      "",
      False,
    )
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })

  file.content
  |> count_occurrences("transport.send_page_init(\"Home\", Nil)")
  |> should.equal(2)

  file.content
  |> count_occurrences("transport.send_page_init(\"About\", Nil)")
  |> should.equal(2)
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  haystack
  |> string.split(needle)
  |> list.length
  |> fn(parts) { parts - 1 }
}

pub fn transport_gleam_exposes_rpc_error_handler_test() {
  let files =
    client.generate_package(
      basic_routes(),
      basic_contracts(),
      test_scan_config(),
      "",
      False,
    )
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "transport.gleam")
    })

  file.content
  |> string.contains(
    "@external(javascript, \"./transport_ffi.mjs\", \"registerRpcErrorHandler\")",
  )
  |> should.equal(True)
  file.content
  |> string.contains(
    "pub fn register_rpc_error_handler(callback: fn(String) -> Nil) -> Nil",
  )
  |> should.equal(True)
  file.content
  |> string.contains(
    "Framework-level errors do not invoke this callback; they flow through",
  )
  |> should.equal(True)
}

pub fn app_gleam_snapshot_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let config = test_scan_config()
  let files = client.generate_package(routes, contracts, config, "", False)
  let app =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })
  let assert Ok(file) = app
  birdie.snap(file.content, "client_app_gleam")
}

pub fn app_gleam_registers_page_push_handlers_test() {
  let route =
    ScannedRoute(
      segments: [StaticSegment("article")],
      variant_name: "Article",
      params: [],
      layout_module: None,
      module_path: "pages/article",
    )
  let contract =
    PageContract(
      model_variants: [
        VariantInfo("Model", [VariantField("count", IntField)]),
      ],
      msg_variants: [
        VariantInfo("Clicked", []),
        VariantInfo("GotServerMsg", [
          VariantField("value", UserType("pages/article", "ToClient", [])),
        ]),
      ],
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
      has_fallible_init: False,
    )
  let config = test_scan_config()
  let files =
    client.generate_package([route], [#(route, contract)], config, "", False)
  let assert Ok(file) =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })

  file.content
  |> string.contains("transport.register_push_handler(\"Article\"")
  |> should.equal(True)

  file.content
  |> string.contains(
    "PageMsg(ArticlePageMsg(pages_article.GotServerMsg(transport.coerce(raw))))",
  )
  |> should.equal(True)
}

pub fn client_page_drops_effect_import_after_send_to_server_rewrite_test() {
  let route =
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: None,
      module_path: "pages/home_",
    )
  let contract =
    PageContract(
      model_variants: [
        VariantInfo("Model", [VariantField("count", IntField)]),
      ],
      msg_variants: [
        VariantInfo("Clicked", []),
      ],
      has_load: False,
      has_init: True,
      has_init_loaded: False,
      has_server_init: False,
      has_server_update: False,
      has_model: True,
      updates_client_context: False,
      param_names: [],
      source: "import lustre/effect.{type Effect}
import rally/runtime/effect as rally_effect

pub type Model { Model(count: Int) }
pub type Msg { Clicked }
pub type ToServer { Increment }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(count: 0), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Clicked -> #(model, rally_effect.send_to_server(Increment))
  }
}
",
      view_source: "",
      init_source: "",
      update_source: "",
      has_page_auth: False,
      page_auth_required: False,
      has_authorize: False,
      has_fallible_init: False,
    )
  let files = codec.generate([#(route, contract)], [], [], [], "etf")
  let assert Ok(file) =
    list.find(files, fn(f: codec.CodecFile) {
      string.contains(f.content, "send_to_server(Increment)")
    })

  file.content
  |> string.contains("import rally/runtime/effect as rally_effect")
  |> should.equal(False)

  file.content
  |> string.contains("send_to_server(Increment)")
  |> should.equal(True)
}

pub fn types_gleam_snapshot_test() {
  let contracts = basic_contracts()
  let files = codec.generate(contracts, [], [], [], "etf")
  let types =
    list.find(files, fn(f: codec.CodecFile) {
      string.ends_with(f.path, "types.gleam")
    })
  let assert Ok(file) = types
  birdie.snap(file.content, "client_types_gleam")
}

pub fn types_gleam_does_not_import_modules_used_only_by_responses_test() {
  let endpoint =
    scanner.HandlerEndpoint(
      module_path: "pages/home_",
      fn_name: "load_home",
      return_ok: UserType("pages/home_", "Model", []),
      return_err: IntField,
      params: [],
      mutates_context: False,
      msg_type: None,
    )
  let files = codec.generate([], [], [endpoint], [], "etf")
  let assert Ok(file) =
    list.find(files, fn(f: codec.CodecFile) {
      string.ends_with(f.path, "types.gleam")
    })

  file.content
  |> string.contains("import pages/home_")
  |> should.equal(False)
}

pub fn codec_ffi_includes_libero_response_decoders_test() {
  let endpoint =
    scanner.HandlerEndpoint(
      module_path: "pages/home_",
      fn_name: "load_home",
      return_ok: UserType("pages/home_", "Model", []),
      return_err: IntField,
      params: [],
      mutates_context: False,
      msg_type: None,
    )
  let files = codec.generate([], [], [endpoint], [], "etf")
  let assert Ok(file) =
    list.find(files, fn(f: codec.CodecFile) {
      string.ends_with(f.path, "codec_ffi.mjs")
    })

  file.content
  |> string.contains("decode_response_load_home")
  |> should.equal(True)
}

pub fn codec_gleam_snapshot_test() {
  let contracts = basic_contracts()
  let files = codec.generate(contracts, [], [], [], "etf")
  let codec_file =
    list.find(files, fn(f: codec.CodecFile) {
      string.ends_with(f.path, "codec.gleam")
    })
  let assert Ok(file) = codec_file
  birdie.snap(file.content, "client_codec_gleam")
}

pub fn codec_gleam_omits_unused_dynamic_type_import_test() {
  let files = codec.generate([], [], [], [], "etf")
  let assert Ok(file) =
    list.find(files, fn(f: codec.CodecFile) {
      string.ends_with(f.path, "codec.gleam")
    })

  file.content
  |> string.contains("type Dynamic")
  |> should.equal(False)
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
    client_root: "client",
    route_root: "/",
    rally_package_path: "",
    shell_file: "",
    server_deps: dict.new(),
    protocol: "etf",
  )
}
