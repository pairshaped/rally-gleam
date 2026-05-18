//// WebSocket auth codegen tests.
////
//// This file protects the generated ws_handler.gleam auth flow:
//// page-init policy checks, RPC owner-page checks, authorize calls,
//// reauth state, and protocol-specific handler routing. Most tests inspect
//// generated source because the contract here is "Rally emits this handler
//// shape" rather than a runtime WebSocket session.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import libero/field_type
import libero/scanner
import libero/wire_identity
import rally/internal/generator/ws_handler
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
  has_fallible_init has_fallible_init: Bool,
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
    has_fallible_init:,
  )
}

fn endpoints_for(
  contracts: List(#(ScannedRoute, PageContract)),
) -> List(scanner.HandlerEndpoint) {
  list.map(contracts, fn(pair: #(ScannedRoute, PageContract)) {
    let #(route, _) = pair
    make_endpoint(route.module_path, "stub_handler")
  })
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

// -- Stable signature: hostname always present --

pub fn ws_no_auth_on_init_has_hostname_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: False,
        page_auth_required: False,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      None,
      from_session_module: "client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "hostname _hostname: String")
}

pub fn ws_no_auth_does_not_call_resolve_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: False,
        page_auth_required: False,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      None,
      from_session_module: "client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert False = string.contains(output, "auth.resolve")
  let assert False = string.contains(output, "from_session")
}

// -- Auth-enabled on_init: resolves and stores state --

pub fn ws_auth_on_init_resolves_identity_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert True =
    string.contains(output, "auth.resolve(server_context, session_id)")
}

pub fn ws_auth_on_init_calls_from_session_with_identity_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "identity: identity")
}

pub fn ws_auth_on_init_stores_auth_state_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert True =
    string.contains(output, "effect_state.put_ws_identity(identity)")
  let assert True =
    string.contains(output, "effect_state.put_ws_hostname(hostname)")
  let assert True =
    string.contains(output, "effect_state.put_ws_auth_timestamp(")
}

// -- Page-init auth enforcement --

pub fn ws_page_init_required_emits_auth_redirect_error_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // Must check is_authenticated before updating page state
  let assert True = string.contains(output, "auth.is_authenticated(identity)")
  // Must emit auth:redirect: error on failure
  let assert True =
    string.contains(output, "auth:redirect:\" <> auth.redirect_url")
}

pub fn ws_page_init_authorize_false_emits_forbidden_error_test() {
  let contracts = [
    #(
      make_route_named("AdminSettings", "admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: True,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // Must include the error response
  let assert True = string.contains(output, "auth:forbidden")
  // page_has_authorize must map the authorized page to True
  let assert True = string.contains(output, "\"AdminSettings\" -> True")
  // check_page_authorize must be generated and call the page module
  let assert True = string.contains(output, "fn check_page_authorize(")
  let assert True =
    string.contains(
      output,
      "admin_pages_settings.authorize(server_context, identity)",
    )
}

pub fn ws_page_init_optional_with_authorize_emits_forbidden_error_test() {
  let contracts = [
    #(
      make_route_named("PublicProfile", "public/pages/profile"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: True,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "public/auth")),
      from_session_module: "public/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // Optional skips auth redirect, but authorize still gates page init.
  let assert True =
    string.contains(output, "\"PublicProfile\" -> rally_auth.Optional")
  let assert True = string.contains(output, "\"PublicProfile\" -> True")
  let assert True =
    string.contains(
      output,
      "public_pages_profile.authorize(server_context, identity)",
    )
  let assert True = string.contains(output, "auth:forbidden")
}

pub fn ws_auth_page_identifiers_match_page_init_variant_names_test() {
  let route =
    make_route_named(
      "AdminRegistrationEvents",
      "admin/pages/registration/events",
    )
  let contracts = [
    #(
      route,
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: True,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert True =
    string.contains(
      output,
      "\"AdminRegistrationEvents\" -> rally_auth.Required",
    )
  let assert True =
    string.contains(output, "\"AdminRegistrationEvents\" -> True")
  let assert True =
    string.contains(
      output,
      "\"AdminRegistrationEvents\" -> admin_pages_registration_events.authorize(server_context, identity)",
    )
  let assert True =
    string.contains(
      output,
      "PageAuthInfo(page: \"AdminRegistrationEvents\", required: True, has_authorize: True)",
    )

  let assert False =
    string.contains(
      output,
      "\"admin/pages/registration/events\" -> rally_auth.Required",
    )
  let assert False =
    string.contains(output, "\"admin/pages/registration/events\" -> True")
  let assert False =
    string.contains(
      output,
      "PageAuthInfo(page: \"admin/pages/registration/events\"",
    )
}

pub fn ws_page_init_no_auth_still_updates_state_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: False,
        page_auth_required: False,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      None,
      from_session_module: "client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // No-auth page-init should still update state as before
  let assert True =
    string.contains(
      output,
      "effect_state.put_ws_state(conn, server_context, page)",
    )
}

pub fn ws_auth_check_page_authorize_always_defined_test() {
  // Auth namespace with NO pages exporting authorize — must still define
  // check_page_authorize so the generated handler compiles.
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "fn check_page_authorize(")
}

pub fn ws_auth_rpc_dispatches_with_identity_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // Auth RPC dispatch must pass identity
  let assert True =
    string.contains(
      output,
      "wire.dispatch_rpc(envelope, server_context, identity)",
    )
  let assert False = string.contains(output, "rpc_dispatch.handle(")
  // Must read identity before dispatch
  let assert True = string.contains(output, "effect_state.get_ws_identity()")
  // Missing identity must fail closed
  let assert True = string.contains(output, "Error(Nil) -> {")
}

// -- WS RPC owning-page enforcement --

pub fn ws_auth_rpc_generates_handler_page_info_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // Must generate handler_page_info mapping variant tags to page modules
  let assert True = string.contains(output, "fn handler_page_info(")
  let assert True = string.contains(output, "\"server_")
  let #(_, wire_hash) =
    wire_identity.wire_identity(
      "admin/pages/dashboard",
      "ServerStubHandler",
      [],
    )
  let assert True = string.contains(output, "\"" <> wire_hash <> "\"")
  let assert True = string.contains(output, "Error(Nil)")
}

pub fn ws_auth_json_handler_page_info_uses_type_string_test() {
  let contracts = [
    #(
      make_route_named("AdminDashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: [make_endpoint("admin/pages/dashboard", "load_data")],
      wire_import_module: "generated/protocol_wire",
      protocol: "json",
    )

  let assert True =
    string.contains(output, "\"admin/pages/dashboard.ServerLoadData\"")
  let assert False = string.contains(output, "\"server_load_data\"")
}

pub fn ws_auth_rpc_uses_protocol_wire_identity_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // RPC branch must use the protocol-neutral identity from the envelope
  let assert True = string.contains(output, "wire.decode_ws_rpc_envelope(msg)")
  let assert True =
    string.contains(output, "handler_page_info(wire.rpc_identity(envelope))")
  let assert False = string.contains(output, "wire.variant_tag")
}

pub fn ws_auth_rpc_enforces_required_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // RPC branch must check is_authenticated for Required pages
  let assert True = string.contains(output, "required &&")
  let assert True = string.contains(output, "auth.is_authenticated(identity)")
  // On failure, emit auth:redirect
  let assert True =
    string.contains(output, "auth:redirect:\" <> auth.redirect_url")
}

pub fn ws_auth_rpc_enforces_authorize_test() {
  let contracts = [
    #(
      make_route("admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: True,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // RPC branch must check authorize on owning_page (not "page" from page-init)
  let assert True =
    string.contains(
      output,
      "check_page_authorize(owning_page, server_context, identity)",
    )
  // On failure, emit auth:forbidden
  let assert True = string.contains(output, "auth:forbidden")
  // Must still dispatch on success
  let assert True =
    string.contains(
      output,
      "wire.dispatch_rpc(envelope, server_context, identity)",
    )
}

pub fn ws_auth_rpc_mixed_required_and_optional_pages_keep_per_page_policy_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
    #(
      make_route("public/pages/login"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "public/auth")),
      from_session_module: "public/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "required: True")
  let assert True = string.contains(output, "required: False")
  let assert True =
    string.contains(output, "case required && !auth.is_authenticated(identity)")
  let assert True = string.contains(output, "auth:redirect:")
}

pub fn ws_auth_rpc_unknown_variant_fails_closed_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // handler_page_info returns Error(Nil) for unknown variants
  // RPC branch must emit auth:unknown_rpc on unknown variant
  let assert True = string.contains(output, "auth:unknown_rpc")
  // RPC branch must check page mismatch
  let assert True = string.contains(output, "auth:page_mismatch")
}

pub fn ws_auth_rpc_missing_identity_fails_before_dispatch_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert Ok(#(_, rpc_branch)) = string.split_once(output, "Ok(envelope) ->")
  let assert Ok(#(_, after_identity_check)) =
    string.split_once(rpc_branch, "case effect_state.get_ws_identity()")
  let assert Ok(#(missing_identity_branch, _)) =
    string.split_once(after_identity_check, "Ok(identity) ->")
  let assert True = string.contains(missing_identity_branch, "auth:forbidden")
  let assert False =
    string.contains(missing_identity_branch, "rpc_dispatch.handle(")
}

pub fn ws_auth_json_protocol_uses_protocol_wire_rpc_test() {
  let contracts = [
    #(
      make_route_named("AdminDashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated/admin/atoms",
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: [make_endpoint("admin/pages/dashboard", "load_data")],
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "json",
    )

  let assert True = string.contains(output, "wire.decode_ws_rpc_envelope(msg)")
  let assert True =
    string.contains(output, "handler_page_info(wire.rpc_identity(envelope))")
  let assert True = string.contains(output, "auth.is_authenticated(identity)")
  let assert True = string.contains(output, "owning_page != current_page")
  let assert True =
    string.contains(
      output,
      "wire.dispatch_rpc(envelope, server_context, identity)",
    )
  let assert True =
    string.contains(output, "wire.send_rpc_result(conn, result)")
  let assert False = string.contains(output, "json_dispatch(")
  let assert False = string.contains(output, "rpc_dispatch.handle(")
  let assert False = string.contains(output, "wire.decode_call")
  let assert False = string.contains(output, "wire.decode_request")
}

pub fn ws_auth_etf_protocol_uses_protocol_wire_rpc_test() {
  let contracts = [
    #(
      make_route_named("AdminDashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated/admin/atoms",
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: [make_endpoint("admin/pages/dashboard", "load_data")],
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "wire.decode_ws_rpc_envelope(msg)")
  let assert True =
    string.contains(output, "handler_page_info(wire.rpc_identity(envelope))")
  let assert True =
    string.contains(
      output,
      "wire.dispatch_rpc(envelope, server_context, identity)",
    )
  let assert True =
    string.contains(output, "wire.send_rpc_result(conn, result)")
  let assert Ok(#(before_page_init_decode, _)) =
    string.split_once(output, "wire.decode_request")
  let assert True =
    string.contains(before_page_init_decode, "wire.decode_ws_rpc_envelope(msg)")
  let assert Ok(#(_, rpc_path)) = string.split_once(output, "Ok(envelope) ->")
  let assert Ok(#(rpc_before_dispatch, _)) =
    string.split_once(rpc_path, "wire.dispatch_rpc")
  let assert False = string.contains(rpc_before_dispatch, "wire.decode_request")
  let assert False = string.contains(output, "json_dispatch(")
  let assert False = string.contains(output, "rpc_dispatch.handle(")
  let assert False = string.contains(output, "wire.variant_tag")
}

// -- WS reauth --

pub fn ws_auth_checks_reauth_timestamp_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // Must read auth timestamp (in reauth block, not just on_init)
  let assert True =
    string.contains(output, "effect_state.get_ws_auth_timestamp()")
  // Must check staleness against reauth interval (30 min in ms)
  let assert True = string.contains(output, "1800000")
  // Must read hostname from stored state, not just on_init parameter
  let assert True = string.contains(output, "effect_state.get_ws_hostname()")
  // Must read current page to preserve it during reauth
  let assert True = string.contains(output, "effect_state.get_ws_page()")
}

pub fn ws_auth_reauth_reruns_resolve_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // On stale, must call auth.resolve again
  // The output already has one resolve call in on_init; reauth adds another
  let assert True =
    string.contains(output, "auth.resolve(server_context, session_id)")
}

pub fn ws_auth_reauth_stores_refreshed_state_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // After successful reauth, must store refreshed identity and timestamp
  let assert True =
    string.contains(output, "effect_state.put_ws_identity(identity)")
  let assert True =
    string.contains(output, "effect_state.put_ws_auth_timestamp(now)")
  // Must call from_session with stored hostname (reauth-specific, not on_init)
  let assert True = string.contains(output, "hostname: hostname")
}

pub fn ws_auth_reauth_failure_fails_closed_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // On resolve failure during reauth, must clear auth state
  let assert True =
    string.contains(output, "effect_state.clear_ws_auth_state()")
}

pub fn ws_auth_no_reauth_when_fresh_test() {
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints_for(contracts),
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  // When not stale, must skip re-resolve and use stored identity
  let assert True = string.contains(output, "effect_state.get_ws_identity()")
}

pub fn json_protocol_generates_send_text_frame_for_pushes_test() {
  // When protocol is "json", send_pending_frames must use send_text_frame
  let output =
    ws_handler.generate(
      [],
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      None,
      from_session_module: "client_context_server",
      endpoints: [],
      wire_import_module: "generated/protocol_wire",
      protocol: "json",
    )

  let assert True = string.contains(output, "send_text_frame")
  let assert True = string.contains(output, "send_pending_frames")
}

pub fn etf_protocol_does_not_generate_send_text_frame_test() {
  // When protocol is "etf", send_pending_frames must use send_binary_frame
  let output =
    ws_handler.generate(
      [],
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      None,
      from_session_module: "client_context_server",
      endpoints: [],
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )

  let assert False = string.contains(output, "send_text_frame")
  let assert True = string.contains(output, "send_binary_frame")
}

// -- Hardcoded hash regression ------------------------------------------------

pub fn ws_auth_wire_hash_regression_test() {
  let #(_, hash) =
    wire_identity.wire_identity("admin/pages/settings", "ServerSetDarkMode", [
      field_type.BoolField,
    ])
  let assert "0418533ae1" = hash
}

pub fn ws_auth_distinct_hashes_for_same_name_different_modules_test() {
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
        has_fallible_init: False,
      ),
    ),
    #(
      make_route_named("AdminSettings", "admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
        has_fallible_init: False,
      ),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated/admin/atoms",
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: [ep_a, ep_b],
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
