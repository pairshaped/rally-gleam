import gleam/option.{None, Some}
import gleam/string
import rally/internal/generator/ssr_handler
import rally/internal/types.{
  type PageContract, type ScannedRoute, AuthConfig, PageContract, ScannedRoute,
  StaticSegment,
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

fn make_route(name: String, module: String) -> ScannedRoute {
  ScannedRoute(
    segments: [StaticSegment(name)],
    variant_name: name,
    params: [],
    module_path: module,
    layout_module: None,
  )
}

const shell = "<html><head></head><body><div id=\"app\"></div></body></html>"

fn generate_with_auth(contract: PageContract, route: ScannedRoute) -> String {
  ssr_handler.generate(
    [#(route, contract)],
    True,
    True,
    "admin/client_context_server",
    "generated/admin/router",
    shell,
    "generated/admin/rpc_atoms",
    None,
    Some("admin/client_context"),
    Some(AuthConfig(auth_module: "admin/auth")),
    wire_import_module: "generated/admin/protocol_wire",
    protocol: "etf",
  )
}

fn generate_without_auth(
  contract: PageContract,
  route: ScannedRoute,
) -> String {
  ssr_handler.generate(
    [#(route, contract)],
    True,
    True,
    "admin/client_context_server",
    "generated/admin/router",
    shell,
    "generated/admin/rpc_atoms",
    None,
    Some("admin/client_context"),
    None,
    wire_import_module: "generated/admin/protocol_wire",
    protocol: "etf",
  )
}

// -- Auth-enabled tests --

pub fn auth_imports_generated_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_with_auth(contract, route)

  let assert True = string.contains(output, "import admin/auth")
  let assert True = string.contains(output, "import rally/runtime/auth")
}

pub fn auth_resolve_called_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_with_auth(contract, route)

  let assert True =
    string.contains(output, "auth.resolve(server_context, session_id)")
}

pub fn auth_required_redirect_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_with_auth(contract, route)

  let assert True = string.contains(output, "auth.is_authenticated(identity)")
  let assert True = string.contains(output, "auth.redirect_url")
}

pub fn auth_optional_no_redirect_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: False,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Login", "public/pages/auth/login")
  let output = generate_with_auth(contract, route)

  let assert True = string.contains(output, "auth.resolve(")
  let assert False = string.contains(output, "auth.is_authenticated(")
}

pub fn auth_from_session_gets_identity_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_with_auth(contract, route)

  let assert True =
    string.contains(
      output,
      "from_session(server_context: server_context, session_id: session_id, hostname: hostname, identity: identity)",
    )
}

pub fn auth_authorize_called_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: True,
      has_fallible_init: False,
    )
  let route = make_route("Managers", "admin/pages/settings/managers")
  let output = generate_with_auth(contract, route)

  let assert True =
    string.contains(
      output,
      "admin_pages_settings_managers.authorize(server_context, identity)",
    )
}

pub fn auth_no_authorize_when_not_exported_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_with_auth(contract, route)

  let assert False = string.contains(output, ".authorize(")
}

pub fn auth_load_receives_identity_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_with_auth(contract, route)

  let assert True = string.contains(output, ".load(server_context, identity)")
}

pub fn auth_load_result_handling_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_with_auth(contract, route)

  let assert True = string.contains(output, "rally_auth.Page(data, cookies)")
  let assert True = string.contains(output, "rally_auth.Redirect(url, cookies)")
  let assert True = string.contains(output, "apply_cookies(")
}

pub fn auth_resolve_error_returns_500_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_with_auth(contract, route)

  let assert True = string.contains(output, "Error(Nil)")
  let assert True = string.contains(output, "500")
}

pub fn auth_shell_resolves_identity_test() {
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  // Add a second route without a load page so the serve_html_shell
  // fallback is generated (it is only emitted when at least one route
  // lacks SSR).
  let no_load_contract =
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
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let other_route = make_route("Other", "admin/pages/other")
  let output =
    ssr_handler.generate(
      [#(route, contract), #(other_route, no_load_contract)],
      True,
      True,
      "admin/client_context_server",
      "generated/admin/router",
      shell,
      "generated/admin/rpc_atoms",
      None,
      Some("admin/client_context"),
      Some(AuthConfig(auth_module: "admin/auth")),
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  let assert True = string.contains(output, "fn serve_html_shell(")
  let assert True = {
    let shell_section = case string.split_once(output, "fn serve_html_shell(") {
      Ok(#(_, after)) -> after
      Error(Nil) -> ""
    }
    string.contains(shell_section, "auth.resolve(")
    && string.contains(shell_section, "identity: identity")
  }
}

// -- No-auth tests (backwards compat) --

pub fn no_auth_unchanged_output_test() {
  let contract =
    make_contract(
      has_page_auth: False,
      page_auth_required: False,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_without_auth(contract, route)

  let assert False = string.contains(output, "auth.resolve")
  let assert False = string.contains(output, "rally/runtime/auth")
  let assert False = string.contains(output, "identity")
  let assert True =
    string.contains(
      output,
      "from_session(server_context: server_context, session_id: session_id, hostname: hostname)",
    )
}

pub fn auth_from_session_without_client_context_test() {
  // P0 regression: auth must call from_session even without ClientContext
  let contract =
    make_contract(
      has_page_auth: True,
      page_auth_required: True,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output =
    ssr_handler.generate(
      [#(route, contract)],
      False,
      True,
      "admin/client_context_server",
      "generated/admin/router",
      shell,
      "generated/admin/rpc_atoms",
      None,
      None,
      Some(AuthConfig(auth_module: "admin/auth")),
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "etf",
    )

  // Must call from_session with identity, discarding ClientContext
  let assert True = string.contains(output, "let #(_, server_context) = ")
  let assert True =
    string.contains(
      output,
      ".from_session(server_context: server_context, session_id: session_id, hostname: hostname, identity: identity)",
    )
  // from_session must run BEFORE load (ordering is the point of this bug)
  let assert True = string.contains(output, ".load(server_context, identity)")
  // Split at from_session; the after part must contain load
  let assert Ok(#(_, after_fs)) =
    string.split_once(output, ".from_session(server_context:")
  let assert True = string.contains(after_fs, ".load(server_context, identity)")
}

pub fn no_auth_cookie_helpers_absent_test() {
  let contract =
    make_contract(
      has_page_auth: False,
      page_auth_required: False,
      has_authorize: False,
      has_fallible_init: False,
    )
  let route = make_route("Dashboard", "admin/pages/dashboard")
  let output = generate_without_auth(contract, route)

  let assert False = string.contains(output, "apply_cookies")
  let assert False = string.contains(output, "LoadResult")
}
