//// Page module parser using Glance AST.
//// Parses page source files to extract the page contract:
//// custom types (ToServer, ToClient) with full variant/field info,
//// and function presence (server_update, server_init, load, etc.).

import glance
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import libero/glance_type_resolver.{RejectUnsupported}
import rally/internal/types.{
  type ClientContextContract, type PageContract, type VariantInfo,
  ClientContextContract, PageContract, VariantField, VariantInfo,
}

/// Parse a page module source to extract the contract.
/// Uses Glance AST parsing for robust type extraction.
pub fn parse_page(
  source source: String,
  module_path module_path: String,
) -> Result(PageContract, String) {
  use ast <- result.try(
    glance.module(source)
    |> result.map_error(fn(e) {
      io.println_error("Parse error: " <> glance_to_string(e))
      "Parse error"
    }),
  )

  use resolver <- result.try(glance_type_resolver.resolver_from_imports(
    ast.imports,
  ))

  use model_variants <- result.try(extract_variants(
    ast: ast,
    type_name: "Model",
    resolver: resolver,
    module_path: module_path,
  ))
  use msg_variants <- result.try(extract_variants(
    ast: ast,
    type_name: "Msg",
    resolver: resolver,
    module_path: module_path,
  ))

  let functions_list = ast.functions
  let has_load = has_function(functions_list, "load")
  let has_init = has_function(functions_list, "init")
  let has_init_loaded = has_function(functions_list, "init_loaded")
  let has_server_init = has_function(functions_list, "server_init")
  let has_server_update = has_function(functions_list, "server_update")
  let has_model =
    has_custom_type(ast.custom_types, "Model")
    || has_type_alias(ast.type_aliases, "Model")

  let param_names = extract_init_params_from_ast(functions_list)

  let view_source =
    extract_function_source(
      source: source,
      functions: functions_list,
      name: "view",
    )
  let init_source =
    extract_function_source(
      source: source,
      functions: functions_list,
      name: "init",
    )
  let update_source =
    extract_function_source(
      source: source,
      functions: functions_list,
      name: "update",
    )
  let updates_client_context = update_returns_client_context_msg(functions_list)

  let #(has_page_auth, page_auth_required) = detect_page_auth(ast.constants)
  let has_authorize = has_function(functions_list, "authorize")
  let has_fallible_init = init_returns_result(functions_list)

  Ok(PageContract(
    model_variants:,
    msg_variants:,
    has_load:,
    has_init:,
    has_init_loaded:,
    has_server_init:,
    has_server_update:,
    has_model:,
    updates_client_context:,
    param_names:,
    source:,
    view_source:,
    init_source:,
    update_source:,
    has_page_auth:,
    page_auth_required:,
    has_authorize:,
    has_fallible_init:,
  ))
}

/// Parse a client_context.gleam source to extract the contract.
pub fn parse_client_context(
  source: String,
) -> Result(ClientContextContract, String) {
  use ast <- result.try(
    glance.module(source)
    |> result.map_error(fn(e) {
      io.println_error("Parse error: " <> glance_to_string(e))
      "Parse error"
    }),
  )

  use resolver <- result.try(glance_type_resolver.resolver_from_imports(
    ast.imports,
  ))

  use context_variants <- result.try(extract_variants(
    ast: ast,
    type_name: "ClientContext",
    resolver: resolver,
    module_path: "client_context",
  ))
  use msg_variants <- result.try(extract_variants(
    ast: ast,
    type_name: "ClientContextMsg",
    resolver: resolver,
    module_path: "client_context",
  ))

  let functions_list = ast.functions
  let has_init = has_function(functions_list, "init")
  let has_update = has_function(functions_list, "update")

  Ok(ClientContextContract(
    context_variants:,
    msg_variants:,
    has_init:,
    has_update:,
  ))
}

// ---------- Type extraction ----------

/// Extract all variants of a named custom type, with field type info.
fn extract_variants(
  ast ast: glance.Module,
  type_name type_name: String,
  resolver resolver: glance_type_resolver.TypeResolver,
  module_path module_path: String,
) -> Result(List(VariantInfo), String) {
  case list.find(ast.custom_types, fn(d) { d.definition.name == type_name }) {
    Error(Nil) -> Ok([])
    Ok(ct_def) -> {
      let custom_type = ct_def.definition
      list.try_map(custom_type.variants, fn(variant) {
        use fields <- result.try(
          list.try_map(variant.fields, fn(field) {
            let #(label, type_) = case field {
              glance.LabelledVariantField(item:, label:) -> #(label, item)
              glance.UnlabelledVariantField(item:) -> #("value", item)
            }
            let path = module_path <> "." <> type_name <> "." <> label
            use ft <- result.try(glance_type_resolver.type_to_field_type(
              type_: type_,
              resolver:,
              current_module: module_path,
              policy: RejectUnsupported(path),
            ))
            Ok(VariantField(label:, type_: ft))
          }),
        )
        Ok(VariantInfo(name: variant.name, fields:))
      })
    }
  }
}

// ---------- Function detection ----------

/// Extract the source text of a named public function using AST span positions.
fn extract_function_source(
  source source: String,
  functions functions: List(glance.Definition(glance.Function)),
  name name: String,
) -> String {
  case
    list.find(functions, fn(def) {
      def.definition.name == name && def.definition.publicity == glance.Public
    })
  {
    Error(Nil) -> ""
    Ok(func_def) -> {
      let glance.Function(location: glance.Span(start:, end:), ..) =
        func_def.definition
      case string.length(source) >= end {
        True -> string.slice(from: source, at_index: start, length: end - start)
        False -> ""
      }
    }
  }
}

fn has_function(
  functions: List(glance.Definition(glance.Function)),
  name: String,
) -> Bool {
  list.any(functions, fn(def) {
    def.definition.name == name && def.definition.publicity == glance.Public
  })
}

fn has_custom_type(
  custom_types: List(glance.Definition(glance.CustomType)),
  name: String,
) -> Bool {
  list.any(custom_types, fn(def) { def.definition.name == name })
}

fn has_type_alias(
  type_aliases: List(glance.Definition(glance.TypeAlias)),
  name: String,
) -> Bool {
  list.any(type_aliases, fn(def) { def.definition.name == name })
}

/// Detect presence and variant of `pub const page_auth = auth.Required/Optional`.
/// Returns #(has_page_auth, page_auth_required).
fn detect_page_auth(
  constants: List(glance.Definition(glance.Constant)),
) -> #(Bool, Bool) {
  list.find_map(constants, fn(def) {
    let glance.Definition(_, constant) = def
    case constant.name {
      "page_auth" -> {
        let is_required = case constant.value {
          glance.FieldAccess(_, glance.Variable(_, _), "Required") -> True
          _ -> False
        }
        Ok(#(True, is_required))
      }
      _ -> Error(Nil)
    }
  })
  |> result.unwrap(#(False, False))
}

/// Extract parameter names from the `init` function AST.
fn extract_init_params_from_ast(
  functions: List(glance.Definition(glance.Function)),
) -> List(String) {
  case
    list.find(functions, fn(def) {
      def.definition.name == "init" && def.definition.publicity == glance.Public
    })
  {
    Error(Nil) -> []
    Ok(func_def) ->
      list.filter_map(func_def.definition.parameters, fn(param) {
        case param {
          glance.FunctionParameter(label: Some(label), ..) -> Ok(label)
          glance.FunctionParameter(
            label: None,
            name: glance.Named(name),
            type_: Some(_),
          ) -> Ok(name)
          _ -> Error(Nil)
        }
      })
  }
}

fn glance_to_string(err: glance.Error) -> String {
  case err {
    glance.UnexpectedEndOfInput -> "unexpected end of input"
    glance.UnexpectedToken(token: _, position:) ->
      "unexpected token at byte offset " <> int.to_string(position.byte_offset)
  }
}

fn init_returns_result(
  functions: List(glance.Definition(glance.Function)),
) -> Bool {
  case
    list.find(functions, fn(def) {
      def.definition.name == "init" && def.definition.publicity == glance.Public
    })
  {
    Ok(def) ->
      case def.definition.return {
        Some(t) -> type_contains_name(t, "Result")
        None -> False
      }
    Error(Nil) -> False
  }
}

fn update_returns_client_context_msg(
  functions: List(glance.Definition(glance.Function)),
) -> Bool {
  case
    list.find(functions, fn(def) {
      def.definition.name == "update"
      && def.definition.publicity == glance.Public
    })
  {
    Ok(def) ->
      case def.definition.return {
        Some(glance.TupleType(elements: [_, _, third], ..)) ->
          type_contains_name(third, "ClientContextMsg")
        _ -> False
      }
    Error(Nil) -> False
  }
}

fn type_contains_name(t: glance.Type, name: String) -> Bool {
  case t {
    glance.NamedType(name: n, parameters:, ..) ->
      n == name || list.any(parameters, fn(p) { type_contains_name(p, name) })
    glance.TupleType(elements:, ..) ->
      list.any(elements, fn(e) { type_contains_name(e, name) })
    glance.FunctionType(parameters:, return:, ..) ->
      list.any(parameters, fn(p) { type_contains_name(p, name) })
      || type_contains_name(return, name)
    glance.VariableType(..) -> False
    glance.HoleType(..) -> False
  }
}
