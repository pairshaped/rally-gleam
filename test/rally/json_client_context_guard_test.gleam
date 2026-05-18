//// Regression: rally build must refuse to generate a JSON-protocol client
//// when any page calls `send_to_client_context`. The JSON encoder for
//// client-context messages is not implemented yet; without this guard the
//// generated code would compile and crash at runtime.

import gleam/option.{None}
import gleam/string
import rally
import rally/internal/types.{
  type PageContract, type ScannedRoute, PageContract, ScannedRoute,
  StaticSegment,
}

fn make_contract(source: String) -> PageContract {
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
    source: source,
    view_source: "",
    init_source: "",
    update_source: "",
    has_page_auth: False,
    page_auth_required: False,
    has_authorize: False,
    has_fallible_init: False,
  )
}

fn make_route(name: String, module: String) -> ScannedRoute {
  ScannedRoute(
    segments: [StaticSegment("page")],
    variant_name: name,
    params: [],
    module_path: module,
    layout_module: None,
  )
}

pub fn etf_protocol_allows_send_to_client_context_test() {
  let contracts = [
    #(
      make_route("Login", "public/pages/login"),
      make_contract("rally_effect.send_to_client_context(SignedIn(user))"),
    ),
  ]
  let assert Ok(Nil) =
    rally.check_json_client_context_compatibility_result(contracts, "etf")
}

pub fn json_protocol_allows_pages_without_client_context_test() {
  let contracts = [
    #(
      make_route("Home", "public/pages/home"),
      make_contract("// no client context here"),
    ),
  ]
  let assert Ok(Nil) =
    rally.check_json_client_context_compatibility_result(contracts, "json")
}

pub fn json_protocol_rejects_pages_with_client_context_test() {
  let contracts = [
    #(
      make_route("Login", "public/pages/login"),
      make_contract("rally_effect.send_to_client_context(SignedIn(user))"),
    ),
  ]
  let assert Error(message) =
    rally.check_json_client_context_compatibility_result(contracts, "json")
  let assert True = string.contains(message, "public/pages/login")
  let assert True = string.contains(message, "rally-au0s")
}

pub fn json_protocol_reports_every_offending_page_test() {
  let contracts = [
    #(
      make_route("Login", "public/pages/login"),
      make_contract("rally_effect.send_to_client_context(SignedIn(user))"),
    ),
    #(make_route("Home", "public/pages/home"), make_contract("// nothing here")),
    #(
      make_route("Settings", "public/pages/settings"),
      make_contract("rally_effect.send_to_client_context(SignedOut)"),
    ),
  ]
  let assert Error(message) =
    rally.check_json_client_context_compatibility_result(contracts, "json")
  let assert True = string.contains(message, "public/pages/login")
  let assert True = string.contains(message, "public/pages/settings")
  let assert False = string.contains(message, "public/pages/home")
}
