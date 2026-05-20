//// HTTP auth codegen tests.
////
//// This file protects generated http_handler.gleam for /rpc requests:
//// resolve, required-page checks, authorize checks, owner-page lookup,
//// protocol-specific wire tags, and HTTP response behavior for auth errors.
//// The tests mostly inspect generated source plus snapshots.

import birdie
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import libero
import libero/field_type
import libero/scanner
import libero/wire_identity
import rally/internal/generator/http_handler
import rally/internal/types.{
  type PageContract, type ScannedRoute, AuthConfig, PageContract, ScannedRoute,
  StaticSegment,
}

fn make_endpoint(module: String, fn_name: String) -> scanner.HandlerEndpoint {
  scanner.HandlerEndpoint(
    module_path: module,
    fn_name: fn_name,
    return_ok: field_type.IntField,
    return_err: field_type.NilField,
    params: [],
    mutates_context: False,
    msg_type: Some(#(module, server_msg_type(fn_name))),
  )
}

fn server_msg_type(fn_name: String) -> String {
  fn_name
  |> string.split("_")
  |> list.map(fn(part) {
    string.uppercase(string.slice(part, at_index: 0, length: 1))
    <> string.slice(part, at_index: 1, length: string.length(part) - 1)
  })
  |> string.join("")
  |> fn(name) { "Server" <> name }
}

fn make_contract(
  has_page_auth has_page_auth: Bool,
  page_auth_required page_auth_required: Bool,
  has_authorize has_authorize: Bool,
) -> PageContract {
  PageContract(
    model_variants: [],
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
    has_page_auth:,
    page_auth_required:,
    has_authorize:,
  )
}

fn make_route(module: String) -> ScannedRoute {
  make_route_named("Test", module)
}

fn make_route_named(name: String, module: String) -> ScannedRoute {
  ScannedRoute(
    segments: [StaticSegment("test")],
    variant_name: name,
    params: [],
    module_path: module,
    layout_module: None,
  )
}

// -- Auth-enabled tests --

pub fn http_auth_imports_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "import admin/auth")
}

pub fn http_auth_resolve_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert True =
    string.contains(output, "auth.resolve(server_context, session_id)")
}

pub fn http_auth_500_on_error_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "Error(Nil)")
  let assert True = string.contains(output, "500")
}

pub fn http_auth_from_session_identity_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "identity: identity")
}

pub fn http_auth_dispatch_gets_identity_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert True =
    string.contains(
      output,
      "wire.dispatch_rpc(envelope, server_context, identity)",
    )
  let assert False = string.contains(output, "rpc_dispatch.handle(")
}

pub fn http_auth_hostname_in_signature_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "hostname hostname: String")
}

// -- No-auth tests --

pub fn http_no_auth_unchanged_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: False,
        page_auth_required: False,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      None,
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert False = string.contains(output, "auth.resolve")
  let assert False = string.contains(output, "identity")
  let assert False = string.contains(output, "hostname")
  let assert True =
    string.contains(output, "import generated/admin/protocol_wire as wire")
  let assert True = string.contains(output, "wire.decode_rpc_envelope(body)")
  let assert True =
    string.contains(output, "wire.dispatch_rpc(envelope, server_context)")
  let assert True =
    string.contains(
      output,
      "response.set_header(\"content-type\", wire.rpc_content_type())",
    )
  let assert True =
    string.contains(output, "mist.Bytes(wire.rpc_result_body(result))")
  let assert False =
    string.contains(output, "import generated/admin/rpc_dispatch")
  let assert False = string.contains(output, "rpc_dispatch.handle(")
}

// -- Wire tag derivation test --

pub fn wire_tag_matches_server_prefix_test() {
  let endpoint = make_endpoint("admin/pages/dashboard", "load_data")
  let dispatch =
    libero.generate_dispatch(
      [endpoint],
      option.Some("generated@rpc_atoms"),
      option.Some("generated@rpc_wire"),
    )
  // Libero's fn_name is "load_data" (without server_ prefix).
  // The wire variant tag should be "server_load_data".
  let assert True = string.contains(dispatch, "\"server_load_data\"")
}

// -- Auth enforcement tests (page-level policy for RPC) --

pub fn http_auth_generates_handler_page_info_test() {
  let endpoints = [
    make_endpoint("admin/pages/dashboard", "load_data"),
    make_endpoint("admin/pages/settings", "update_config"),
  ]
  let contracts = [
    #(
      make_route_named("AdminDashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
    #(
      make_route_named("AdminSettings", "admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: True,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  // Should contain handler_page_info mapping both endpoints
  let assert True = string.contains(output, "fn handler_page_info(")
  let assert True = string.contains(output, "\"server_load_data\"")
  let assert True = string.contains(output, "\"server_update_config\"")
  let #(_, load_hash) =
    wire_identity.wire_identity("admin/pages/dashboard", "ServerLoadData", [])
  let #(_, update_hash) =
    wire_identity.wire_identity(
      "admin/pages/settings",
      "ServerUpdateConfig",
      [],
    )
  let assert True = string.contains(output, "\"" <> load_hash <> "\"")
  let assert True = string.contains(output, "\"" <> update_hash <> "\"")
  let assert True =
    string.contains(
      output,
      "PageAuthInfo(page: \"AdminDashboard\", required: True, has_authorize: False)",
    )
  let assert True =
    string.contains(
      output,
      "PageAuthInfo(page: \"AdminSettings\", required: False, has_authorize: True)",
    )
  let assert False =
    string.contains(output, "PageAuthInfo(page: \"admin/pages/dashboard\"")
  let assert False =
    string.contains(output, "PageAuthInfo(page: \"admin/pages/settings\"")
}

pub fn http_auth_json_handler_page_info_uses_type_string_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route_named("AdminDashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "json",
    )

  let assert True =
    string.contains(output, "\"admin/pages/dashboard.ServerLoadData\"")
  let assert False = string.contains(output, "\"server_load_data\"")
}

pub fn http_auth_required_page_returns_401_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  // Required pages must check is_authenticated before dispatch
  let assert True = string.contains(output, "auth.is_authenticated(identity)")
  let assert True = string.contains(output, "401")
}

pub fn http_auth_optional_page_dispatches_test() {
  let endpoints = [make_endpoint("public/pages/about", "get_info")]
  let contracts = [
    #(
      make_route("public/pages/about"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/public/rpc_dispatch",
      Some(AuthConfig(auth_module: "public/auth")),
      contracts,
      from_session_module: "public/client_context_server",
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  // Optional pages should NOT check is_authenticated
  let assert False = string.contains(output, "auth.is_authenticated(identity)")
  // But should still resolve and dispatch
  let assert True = string.contains(output, "auth.resolve(")
  let assert True = string.contains(output, "wire.dispatch_rpc(")
  let assert False = string.contains(output, "rpc_dispatch.handle(")
}

pub fn http_auth_optional_page_with_authorize_returns_403_test() {
  let endpoints = [make_endpoint("public/pages/profile", "update_profile")]
  let contracts = [
    #(
      make_route_named("PublicProfile", "public/pages/profile"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: True,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/public/rpc_dispatch",
      Some(AuthConfig(auth_module: "public/auth")),
      contracts,
      from_session_module: "public/client_context_server",
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  // Optional skips redirect-style authentication, but authorize still applies.
  let assert False = string.contains(output, "auth.is_authenticated(identity)")
  let assert True = string.contains(output, "fn check_page_authorize(")
  let assert True = string.contains(output, "\"PublicProfile\" ->")
  let assert True =
    string.contains(
      output,
      "public_pages_profile.authorize(server_context, identity)",
    )
  let assert True = string.contains(output, "403")
}

pub fn http_auth_mixed_required_and_optional_pages_keep_per_page_policy_test() {
  let endpoints = [
    make_endpoint("admin/pages/dashboard", "load_data"),
    make_endpoint("public/pages/login", "submit_login"),
  ]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
    #(
      make_route("public/pages/login"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/public/rpc_dispatch",
      Some(AuthConfig(auth_module: "public/auth")),
      contracts,
      from_session_module: "public/client_context_server",
      wire_import_module: "generated/public/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "\"server_load_data\"")
  let assert True = string.contains(output, "\"server_submit_login\"")
  let assert True = string.contains(output, "required: True")
  let assert True = string.contains(output, "required: False")
  let assert True =
    string.contains(output, "case required && !auth.is_authenticated(identity)")
}

pub fn http_auth_authorize_false_returns_403_test() {
  let endpoints = [make_endpoint("admin/pages/settings", "update_config")]
  let contracts = [
    #(
      make_route("admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: True,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  // Should generate check_page_authorize function
  let assert True = string.contains(output, "fn check_page_authorize(")
  // Should call authorize on the page module
  let assert True =
    string.contains(
      output,
      "admin_pages_settings.authorize(server_context, identity)",
    )
  // Should return 403 on auth failure
  let assert True = string.contains(output, "403")
}

pub fn http_auth_unknown_variant_returns_400_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  // handler_page_info returns Error(Nil) for unknown variants
  // The handle function must handle this case
  let assert True = string.contains(output, "Error(Nil)")
  // Should return 400 (not fall through to dispatch)
  // The existing 500 is from resolve Error; we need a distinct 400 for unknown variant
  let assert True = string.contains(output, "400")
}

pub fn http_auth_malformed_body_returns_400_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  // decode_rpc_envelope failure should return 400
  let assert True = string.contains(output, "wire.decode_rpc_envelope(body)")
  let assert True = string.contains(output, "Error(Nil)")
}

pub fn http_auth_uses_rpc_identity_from_protocol_wire_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert True =
    string.contains(output, "handler_page_info(wire.rpc_identity(envelope))")
  let assert False = string.contains(output, "wire.decode_call")
  let assert False = string.contains(output, "wire.variant_tag")
  let assert False = string.contains(output, "wire.decode_request")
}

pub fn http_auth_json_dispatches_through_protocol_wire_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "json",
    )

  let assert True = string.contains(output, "wire.decode_rpc_envelope(body)")
  let assert True =
    string.contains(output, "handler_page_info(wire.rpc_identity(envelope))")
  let assert True =
    string.contains(
      output,
      "wire.dispatch_rpc(envelope, server_context, identity)",
    )
  let assert True =
    string.contains(
      output,
      "response.set_header(\"content-type\", wire.rpc_content_type())",
    )
  let assert True =
    string.contains(output, "mist.Bytes(wire.rpc_result_body(result))")
  let assert False = string.contains(output, "Not implemented")
  let assert False = string.contains(output, "rpc_dispatch.handle(")
  let assert False = string.contains(output, "wire.decode_request")
}

// Missing-contract case is not tested here because it panics at codegen
// time. An endpoint with no matching PageContract is an invariant violation
// between Libero's scan and Rally's parser — it should never happen.

pub fn http_auth_imports_protocol_wire_facade_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  // Must import the protocol_wire facade, not rally/runtime/wire
  let assert True =
    string.contains(output, "import generated/admin/protocol_wire as wire")
  // Must NOT import rally/runtime/wire directly
  let assert False = string.contains(output, "import rally/runtime/wire")
  // Must NOT import an Erlang module as wire
  let assert False = string.contains(output, "generated@")
}

// -- Snapshot tests --

pub fn http_handler_no_auth_snapshot_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: False,
        page_auth_required: False,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      None,
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )
  birdie.snap(output, "http_handler_no_auth")
}

pub fn http_handler_with_auth_required_snapshot_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )
  birdie.snap(output, "http_handler_with_auth_required")
}

pub fn http_handler_with_auth_and_authorize_snapshot_test() {
  let endpoints = [
    make_endpoint("admin/pages/dashboard", "load_data"),
    make_endpoint("admin/pages/settings", "update_config"),
  ]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
    #(
      make_route("admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: True,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )
  birdie.snap(output, "http_handler_with_auth_and_authorize")
}

// -- Hardcoded hash regression ------------------------------------------------

pub fn http_auth_wire_hash_regression_test() {
  let #(_, hash) =
    wire_identity.wire_identity("admin/pages/settings", "ServerSetDarkMode", [
      field_type.BoolField,
    ])
  let assert "0418533ae1" = hash
}

pub fn http_auth_distinct_hashes_for_same_name_different_modules_test() {
  let ep_a =
    scanner.HandlerEndpoint(
      module_path: "admin/pages/dashboard",
      fn_name: "set_dark_mode",
      return_ok: field_type.NilField,
      return_err: field_type.NilField,
      params: [#("enabled", field_type.BoolField)],
      mutates_context: False,
      msg_type: Some(#("admin/pages/dashboard", "ServerSetDarkMode")),
    )
  let ep_b =
    scanner.HandlerEndpoint(
      module_path: "admin/pages/settings",
      fn_name: "set_dark_mode_settings",
      return_ok: field_type.NilField,
      return_err: field_type.NilField,
      params: [#("enabled", field_type.BoolField)],
      mutates_context: False,
      msg_type: Some(#("admin/pages/settings", "ServerSetDarkMode")),
    )
  let contracts = [
    #(
      make_route_named("AdminDashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
    #(
      make_route_named("AdminSettings", "admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      [ep_a, ep_b],
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )
  let #(_, hash_a) =
    wire_identity.wire_identity("admin/pages/dashboard", "ServerSetDarkMode", [
      field_type.BoolField,
    ])
  let #(_, hash_b) =
    wire_identity.wire_identity("admin/pages/settings", "ServerSetDarkMode", [
      field_type.BoolField,
    ])
  let assert True = hash_a != hash_b
  let assert True = string.contains(output, "\"" <> hash_a <> "\"")
  let assert True = string.contains(output, "\"" <> hash_b <> "\"")
  let assert True =
    string.contains(output, "PageAuthInfo(page: \"AdminDashboard\"")
  let assert True =
    string.contains(output, "PageAuthInfo(page: \"AdminSettings\"")
}
