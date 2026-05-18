//// Central type vocabulary for the codegen pipeline.
////
//// These types flow between the scanner, parser, and generators.
//// The scanner produces ScannedRoutes. The parser produces PageContracts.
//// The generators consume both to emit server handlers, client packages,
//// and everything in between. ScanConfig carries the per-namespace
//// configuration that drives the whole pipeline.

import gleam/dict.{type Dict}
import gleam/option.{type Option}
import libero/field_type.{type FieldType}
import tom

/// How a dynamic URL segment's value is parsed.
/// The scanner assigns IntParam to segments named "id" or ending in "_id",
/// and StringParam to everything else.
pub type ParamType {
  IntParam
  StringParam
}

/// One segment of a URL path. StaticSegment is a literal match ("settings"),
/// DynamicSegment captures a value from the URL ("id_" becomes :id).
pub type UrlSegment {
  StaticSegment(name: String)
  DynamicSegment(param_name: String, param_type: ParamType)
}

/// A route discovered by the scanner from the filesystem.
/// Created by scanner.scan, consumed by every generator module.
pub type ScannedRoute {
  ScannedRoute(
    /// URL path broken into static and dynamic parts.
    segments: List(UrlSegment),
    /// PascalCase name for the Route type variant (e.g., "SettingsGeneral").
    variant_name: String,
    /// Dynamic segments extracted as a flat list for codegen convenience.
    params: List(#(String, ParamType)),
    /// Gleam module path relative to src/ (e.g., "public/pages/settings/general").
    module_path: String,
    /// Nearest ancestor layout.gleam, if one exists in the directory tree.
    layout_module: Option(String),
  )
}

/// Configuration for one codegen run. Each [[tools.rally.clients]] entry
/// in gleam.toml becomes one ScanConfig. Created in rally.gleam from
/// TOML parsing, threaded through the entire pipeline.
pub type ScanConfig {
  ScanConfig(
    /// Filesystem path to the pages directory (e.g., "src/public/pages").
    pages_root: String,
    /// Output path for generated router.gleam.
    output_route: String,
    /// Output path for generated page_dispatch.gleam (PageModel/PageMsg unions).
    output_dispatch: String,
    /// Output path for generated rpc_dispatch.gleam (libero RPC dispatch).
    output_server_dispatch: String,
    /// Output path for the Erlang atoms module (ETF type registrations).
    output_server_atoms: String,
    /// Erlang module name for the atoms file (e.g., "generated@public@rpc_atoms").
    atoms_module: String,
    /// Output path for the Erlang wire module (ETF encode/decode dispatch).
    output_server_wire: String,
    /// Erlang module name for the wire file.
    wire_module: String,
    /// Output path for generated ssr_handler.gleam.
    output_ssr: String,
    /// Output path for generated ws_handler.gleam.
    output_ws: String,
    /// Output path for generated http_handler.gleam.
    output_http: String,
    /// Root of the generated client package (e.g., ".generated_clients/public").
    client_root: String,
    /// URL prefix for this namespace's routes (e.g., "/admin"). Defaults to "/".
    route_root: String,
    /// Filesystem path to the rally package itself (for copying transport_ffi.mjs).
    rally_package_path: String,
    /// Path to the HTML shell template (e.g., "src/public/shell.html").
    shell_file: String,
    /// The [dependencies] table from gleam.toml, used when generating the
    /// client package's gleam.toml.
    server_deps: Dict(String, tom.Toml),
    /// Wire protocol: "etf" (default) or "json".
    protocol: String,
  )
}

/// A single field in a variant constructor. The label is the field name,
/// type_ is the resolved FieldType from libero's type system.
pub type VariantField {
  VariantField(label: String, type_: FieldType)
}

/// A single variant in a custom type. Used to represent Model variants,
/// Msg variants, ClientContext variants, and handler message types.
pub type VariantInfo {
  VariantInfo(name: String, fields: List(VariantField))
}

/// What the parser extracted from a client_context.gleam file.
/// Created by parser.parse_client_context, consumed by client package
/// generation to wire up context init and update in the generated app.
pub type ClientContextContract {
  ClientContextContract(
    /// Variants of the ClientContext type.
    context_variants: List(VariantInfo),
    /// Variants of the ClientContextMsg type.
    msg_variants: List(VariantInfo),
    /// Whether client_context.gleam exports pub fn init.
    has_init: Bool,
    /// Whether client_context.gleam exports pub fn update.
    has_update: Bool,
  )
}

/// Auth configuration for a namespace. Present when the namespace has
/// an auth.gleam that exports Identity, resolve, is_authenticated,
/// and redirect_url.
pub type AuthConfig {
  /// Gleam module path for the auth module (e.g., "admin/auth").
  AuthConfig(auth_module: String)
}

/// Everything the parser extracted from a single page module.
/// Created by parser.parse_page, consumed by every generator.
/// This is the contract that tells generators what the page exports,
/// what types it defines, and what features it opts into.
pub type PageContract {
  PageContract(
    /// Variants of the page's pub type Model.
    model_variants: List(VariantInfo),
    /// Variants of the page's pub type Msg.
    msg_variants: List(VariantInfo),
    /// Page exports pub fn load (SSR data loading).
    has_load: Bool,
    /// Page exports pub fn init (client-side initialization).
    has_init: Bool,
    /// Page exports pub fn init_loaded (client init from SSR-loaded data).
    has_init_loaded: Bool,
    /// Page exports pub fn server_init (server-side stateful page init).
    has_server_init: Bool,
    /// Page exports pub fn server_update (server-side stateful page update).
    has_server_update: Bool,
    /// Page defines a Model type (custom type or alias). Pages without
    /// a Model are static content with no client-side state.
    has_model: Bool,
    /// The update function returns a 3-tuple including Option(ClientContextMsg),
    /// meaning this page can modify shared client context.
    updates_client_context: Bool,
    /// Parameter names from the init function signature. Used to generate
    /// route-param threading in the client app (e.g., ["id", "slug"]).
    param_names: List(String),
    /// Full source text of the page file. Kept for tree-shaking.
    source: String,
    /// Extracted source of the view function. Used by client codegen.
    view_source: String,
    /// Extracted source of the init function. Used by client codegen.
    init_source: String,
    /// Extracted source of the update function. Used by client codegen.
    update_source: String,
    /// Page declares pub const page_auth (Required or Optional).
    has_page_auth: Bool,
    /// page_auth is auth.Required (must be authenticated to view).
    page_auth_required: Bool,
    /// Page exports pub fn authorize (role/permission-level access control).
    has_authorize: Bool,
    /// init returns Result(#(Model, Effect(Msg)), Nil) instead of #(Model, Effect(Msg)).
    /// Pages that parse route params (e.g., int.parse on an id) return Error(Nil)
    /// for invalid params, which the generated dispatch renders as 404.
    has_fallible_init: Bool,
  )
}
