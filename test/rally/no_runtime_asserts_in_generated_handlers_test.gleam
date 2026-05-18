//// Regression: generated WS handlers must never use `let assert Ok(...)`
//// for runtime infrastructure lookups (server_context, system_db conn).
//// Those failures need a logged error response, not a panic that takes the
//// whole websocket connection down.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import libero/field_type
import libero/scanner
import rally/internal/generator/ws_handler
import rally/internal/types.{
  type PageContract, type ScannedRoute, AuthConfig, PageContract, ScannedRoute,
  StaticSegment,
}

const banned_substrings = [
  "let assert Ok(server_context) = effect_state.get_stored_server_context()",
  "let assert Ok(db_conn) = system_db.get_conn()",
]

fn assert_no_runtime_asserts(output: String, label: String) -> Nil {
  list.each(banned_substrings, fn(banned) {
    case string.contains(output, banned) {
      False -> Nil
      True ->
        panic as {
          label
          <> ": generated handler still contains forbidden assert: "
          <> banned
        }
    }
  })
}

/// Confirm the missing-server_context page_init branch sends a response frame
/// (not just a log + continue). The client is waiting on `request_id` and
/// will hang without a frame back.
fn assert_page_init_missing_context_emits_response(
  output: String,
  label: String,
) -> Nil {
  let assert Ok(#(_, after_log)) =
    string.split_once(output, "failing page_init for")
  let assert Ok(#(window, _)) = string.split_once(after_log, "mist.continue")
  case
    string.contains(
      window,
      "wire.encode_response(request_id:, value: Error(\"server_unavailable\"))",
    )
    && string.contains(window, "mist.send_binary_frame")
  {
    True -> Nil
    False ->
      panic as {
        label
        <> ": page_init missing-context branch does not emit a response frame "
        <> "before mist.continue. Window between log and continue:\n"
        <> window
      }
  }
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
    has_page_auth: has_page_auth,
    page_auth_required: page_auth_required,
    has_authorize: has_authorize,
  )
}

fn make_route(name: String, module: String) -> ScannedRoute {
  ScannedRoute(
    segments: [StaticSegment("test")],
    variant_name: name,
    params: [],
    module_path: module,
    layout_module: None,
  )
}

fn make_endpoint(module: String) -> scanner.HandlerEndpoint {
  scanner.HandlerEndpoint(
    module_path: module,
    fn_name: "save",
    return_ok: field_type.IntField,
    return_err: field_type.NilField,
    params: [],
    mutates_context: False,
    msg_type: Some(#(module, "ServerSave")),
  )
}

pub fn ws_no_auth_etf_has_no_runtime_asserts_test() {
  let contracts = [
    #(
      make_route("Dashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: False,
        page_auth_required: False,
        has_authorize: False,
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
      endpoints: [make_endpoint("admin/pages/dashboard")],
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )
  assert_no_runtime_asserts(output, "ws_no_auth_etf")
  assert_page_init_missing_context_emits_response(output, "ws_no_auth_etf")
}

pub fn ws_no_auth_json_has_no_runtime_asserts_test() {
  let contracts = [
    #(
      make_route("Dashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: False,
        page_auth_required: False,
        has_authorize: False,
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
      endpoints: [make_endpoint("admin/pages/dashboard")],
      wire_import_module: "generated/protocol_wire",
      protocol: "json",
    )
  assert_no_runtime_asserts(output, "ws_no_auth_json")
}

pub fn ws_auth_etf_with_endpoints_has_no_runtime_asserts_test() {
  let contracts = [
    #(
      make_route("AdminSettings", "admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: True,
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
      endpoints: [make_endpoint("admin/pages/settings")],
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )
  assert_no_runtime_asserts(output, "ws_auth_etf")
  assert_page_init_missing_context_emits_response(output, "ws_auth_etf")
}

pub fn ws_auth_json_with_endpoints_has_no_runtime_asserts_test() {
  let contracts = [
    #(
      make_route("AdminSettings", "admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: True,
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
      endpoints: [make_endpoint("admin/pages/settings")],
      wire_import_module: "generated/protocol_wire",
      protocol: "json",
    )
  assert_no_runtime_asserts(output, "ws_auth_json")
}

pub fn ws_auth_no_endpoints_has_no_runtime_asserts_test() {
  let contracts = [
    #(
      make_route("AdminSettings", "admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
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
      endpoints: [],
      wire_import_module: "generated/protocol_wire",
      protocol: "etf",
    )
  assert_no_runtime_asserts(output, "ws_auth_no_endpoints")
}
