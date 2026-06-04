//// ETF RPC dispatch generation.
////
//// Rally owns handler routing and request/result workflow. This module
//// consumes Libero's endpoint/type metadata and emits Rally-owned dispatch
//// glue that calls page handlers and delegates only wire encoding/decoding to
//// Libero runtime/generated helpers.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import libero/field_type.{
  type FieldType, DictOf, ListOf, OptionOf, ResultOf, TupleOf, UserType,
}
import libero/scanner.{type HandlerEndpoint}

pub type ExtraParam {
  ExtraParam(name: String, type_ref: String, import_line: String)
}

pub fn generate(
  endpoints endpoints: List(HandlerEndpoint),
  atoms_module atoms_module: Option(String),
  wire_module wire_module: Option(String),
) -> String {
  generate_with_extra_params(
    endpoints:,
    atoms_module:,
    wire_module:,
    extra_params: [],
  )
}

pub fn generate_with_extra_params(
  endpoints endpoints: List(HandlerEndpoint),
  atoms_module atoms_module: Option(String),
  wire_module wire_module: Option(String),
  extra_params extra_params: List(ExtraParam),
) -> String {
  let handler_modules =
    endpoints
    |> list.map(fn(endpoint) { endpoint.module_path })
    |> list.unique
  let handler_imports =
    handler_modules
    |> list.map(fn(module_path) {
      "import " <> module_path <> " as " <> handler_alias(module_path)
    })

  let resolve_alias = alias_resolver(endpoints, handler_modules)
  let shared_type_imports =
    collect_dispatch_type_modules(endpoints)
    |> list.filter(fn(module_path) {
      !list.contains(handler_modules, module_path)
    })
    |> list.map(fn(module_path) {
      let alias = resolve_alias(module_path)
      case alias == field_type.last_segment(module_path) {
        True -> "import " <> module_path
        False -> "import " <> module_path <> " as " <> alias
      }
    })

  let extra_imports =
    extra_params
    |> list.filter(fn(param) { param.import_line != "" })
    |> list.map(fn(param) { param.import_line })
    |> list.unique
  let extra_handle_params =
    extra_params
    |> list.map(fn(param) {
      "\n  "
      <> param.name
      <> " "
      <> unused_param_name(param.name, endpoints)
      <> ": "
      <> param.type_ref
      <> ","
    })
    |> string.join("")
  let extra_args =
    extra_params
    |> list.map(fn(param) { ", " <> param.name })
    |> string.join("")

  let client_msg_variants = case endpoints {
    [] -> "  NoClientMessages"
    _ ->
      endpoints
      |> list.map(fn(endpoint) { client_msg_variant(endpoint, resolve_alias:) })
      |> string.join("\n")
  }
  let known_tag_arms =
    endpoints
    |> list.map(fn(endpoint) {
      "        Ok(\"server_"
      <> endpoint.fn_name
      <> "\") ->\n"
      <> "          dispatch_known(msg, request_id, server_context"
      <> extra_args
      <> ")"
    })
    |> string.join("\n")
  let case_arms =
    endpoints
    |> list.map(emit_case_arm(_, wire_module:, extra_args:, resolve_alias:))
    |> string.join("\n")

  let atoms_external = case atoms_module {
    Some(module_name) ->
      "\n/// Pre-register all constructor atoms that may appear in client ETF
/// payloads, so binary_to_term([safe]) can decode them. Called once
/// on the first RPC call; subsequent calls are a no-op.
@external(erlang, \"" <> module_name <> "\", \"ensure\")
fn ensure_atoms() -> Nil
"
    None -> ""
  }
  let ensure_call = case atoms_module {
    Some(_) -> "  ensure_atoms()\n  "
    None -> ""
  }

  let inner_case = case endpoints {
    [] ->
      "        Ok(_) ->
          #(wire.encode_response(request_id:, value: Error(UnknownFunction(\"rpc\"))), server_context)
        Error(_) ->
          #(wire.encode_response(request_id:, value: Error(MalformedRequest)), server_context)"
    _ -> known_tag_arms <> "\n" <> "        Ok(tag) ->
          #(wire.encode_response(request_id:, value: Error(UnknownFunction(\"rpc.\" <> tag))), server_context)
        Error(_) ->
          #(wire.encode_response(request_id:, value: Error(MalformedRequest)), server_context)"
  }

  let wire_externals = wire_externals(wire_module:, endpoints:)
  let should_decode_msg = case wire_module, endpoints {
    Some(_), [_, ..] -> True
    _, _ -> False
  }
  let rpc_dispatch_body = case should_decode_msg {
    True -> "      case trace.try_call(fn() {
        let msg = wire_decode_client_msg(msg)
        case wire.variant_tag(msg) {
" <> inner_case <> "
        }
      }) {
        Ok(response) -> response
        Error(reason) -> {
          let trace_id = trace.new_trace_id()
          io.println_error(\"[rally] \" <> trace_id <> \" malformed message: \" <> reason)
          #(wire.encode_response(request_id:, value: Error(MalformedRequest)), server_context)
        }
      }"
    False -> "      case wire.variant_tag(msg) {
" <> inner_case <> "
      }"
  }
  let dispatch_known = case endpoints {
    [] -> ""
    _ -> "
fn dispatch_known(msg, request_id, server_context" <> extra_args <> ") {
  case trace.try_call(fn() {
    let typed_msg: ClientMsg = wire.coerce(msg)
    case typed_msg {
" <> case_arms <> "
    }
  }) {
    Ok(response) -> response
    Error(reason) -> {
      let trace_id = trace.new_trace_id()
      io.println_error(\"[rally] \" <> trace_id <> \" malformed message: \" <> reason)
      #(wire.encode_response(request_id:, value: Error(MalformedRequest)), server_context)
    }
  }
}
"
  }

  "// Generated by Rally. Do not edit.

import gleam/io
import libero/error.{InternalError, MalformedRequest, UnknownFunction}
import libero/etf/wire
import libero/trace" <> conditional_import(
    endpoints,
    contains_dict,
    "import gleam/dict.{type Dict}",
  ) <> conditional_import(
    endpoints,
    contains_option,
    "import gleam/option.{type Option}",
  ) <> "\nimport server_context.{type ServerContext}
" <> join_imports(handler_imports) <> join_imports(shared_type_imports) <> join_imports(
    extra_imports,
  ) <> atoms_external <> wire_externals <> "
pub type ClientMsg {
" <> client_msg_variants <> "
}

pub fn handle(
  server_context server_context: ServerContext,
  data data: BitArray," <> extra_handle_params <> "
) -> #(BitArray, ServerContext) {
  " <> ensure_call <> "case wire.decode_request(data) {
    Ok(#(\"rpc\", request_id, msg)) -> {
" <> rpc_dispatch_body <> "
    }
    Ok(#(name, request_id, _)) ->
      #(wire.encode_response(request_id:, value: Error(UnknownFunction(name))), server_context)
    Error(_) ->
      #(wire.encode_response(request_id: 0, value: Error(MalformedRequest)), server_context)
  }
}
" <> dispatch_known
}

fn wire_externals(
  wire_module wire_module: Option(String),
  endpoints endpoints: List(HandlerEndpoint),
) -> String {
  case wire_module, endpoints {
    Some(module_name), [_, ..] -> {
      let decode =
        "\n@external(erlang, \"" <> module_name <> "\", \"decode_client_msg\")
fn wire_decode_client_msg(msg: a) -> b
"
      let encoders =
        endpoints
        |> list.map(fn(endpoint) {
          "@external(erlang, \""
          <> module_name
          <> "\", \"encode_response_"
          <> endpoint.fn_name
          <> "\")
fn wire_encode_response_"
          <> endpoint.fn_name
          <> "(result: a) -> b
"
        })
        |> string.join("\n")
      decode <> "\n" <> encoders
    }
    _, _ -> ""
  }
}

fn emit_case_arm(
  endpoint endpoint: HandlerEndpoint,
  wire_module wire_module: Option(String),
  extra_args extra_args: String,
  resolve_alias resolve_alias: fn(String) -> String,
) -> String {
  let variant_name = to_pascal_case("server_" <> endpoint.fn_name)
  let alias = handler_alias(endpoint.module_path)
  let param_destructure =
    variant_pattern(variant_name:, params: endpoint.params)
  let handler_args = case endpoint.msg_type {
    Some(#(msg_module, msg_constructor)) ->
      msg_type_constructor(
        module_path: msg_module,
        constructor_name: msg_constructor,
        params: endpoint.params,
        resolve_alias:,
      )
      <> ", server_context"
      <> extra_args
    None -> {
      let positional = list.map(endpoint.params, fn(param) { param.0 })
      string.join(
        list.append(positional, ["server_context" <> extra_args]),
        ", ",
      )
    }
  }
  let raw_call =
    alias <> ".server_" <> endpoint.fn_name <> "(" <> handler_args <> ")"
  let ok_destructure = case endpoint.mutates_context {
    True -> "#(result, new_ctx)"
    False -> "result"
  }
  let ok_ctx = case endpoint.mutates_context {
    True -> "new_ctx"
    False -> "server_context"
  }
  let encode_line = case wire_module {
    Some(_) ->
      "              let result = wire_encode_response_"
      <> endpoint.fn_name
      <> "(result)\n"
    None -> ""
  }

  "        " <> param_destructure <> " -> {
          case trace.try_call(fn() { " <> raw_call <> " }) {
            Ok(" <> ok_destructure <> ") -> {
" <> encode_line <> "              #(wire.encode_response(request_id:, value: Ok(result)), " <> ok_ctx <> ")
            }
            Error(reason) -> {
              let trace_id = trace.new_trace_id()
              io.println_error(\"[rally] \" <> trace_id <> \" " <> endpoint.fn_name <> ": \" <> reason)
              #(wire.encode_response(request_id:, value: Error(InternalError(trace_id:, message: \"Something went wrong\"))), server_context)
            }
          }
        }"
}

fn client_msg_variant(
  endpoint endpoint: HandlerEndpoint,
  resolve_alias resolve_alias: fn(String) -> String,
) -> String {
  case endpoint.msg_type {
    Some(#(_, type_name)) ->
      "  " <> type_name <> variant_fields(endpoint.params, resolve_alias)
    None -> {
      let variant_name = to_pascal_case("server_" <> endpoint.fn_name)
      "  " <> variant_name <> variant_fields(endpoint.params, resolve_alias)
    }
  }
}

fn variant_fields(
  params params: List(#(String, FieldType)),
  resolve_alias resolve_alias: fn(String) -> String,
) -> String {
  case params {
    [] -> ""
    _ -> {
      let fields =
        params
        |> list.map(fn(param) {
          param.0
          <> ": "
          <> field_type.to_gleam_source_with_alias(param.1, resolve_alias)
        })
        |> string.join(", ")
      "(" <> fields <> ")"
    }
  }
}

fn variant_pattern(
  variant_name variant_name: String,
  params params: List(#(String, FieldType)),
) -> String {
  case params {
    [] -> variant_name
    _ -> {
      let labels =
        params
        |> list.map(fn(param) { param.0 <> ":" })
        |> string.join(", ")
      variant_name <> "(" <> labels <> ")"
    }
  }
}

fn msg_type_constructor(
  module_path module_path: String,
  constructor_name constructor_name: String,
  params params: List(#(String, FieldType)),
  resolve_alias resolve_alias: fn(String) -> String,
) -> String {
  let constructor = resolve_alias(module_path) <> "." <> constructor_name
  case params {
    [] -> constructor
    _ -> {
      let labels = list.map(params, fn(param) { param.0 <> ":" })
      constructor <> "(" <> string.join(labels, ", ") <> ")"
    }
  }
}

fn alias_resolver(
  endpoints: List(HandlerEndpoint),
  handler_modules: List(String),
) -> fn(String) -> String {
  let type_modules = collect_dispatch_type_modules(endpoints)
  let all_modules = list.append(handler_modules, type_modules) |> list.unique
  let duplicate_last_segments =
    all_modules
    |> list.map(field_type.last_segment)
    |> duplicates

  fn(module_path: String) -> String {
    case list.contains(handler_modules, module_path) {
      True -> handler_alias(module_path)
      False -> {
        let last = field_type.last_segment(module_path)
        case list.contains(duplicate_last_segments, last) {
          True -> module_to_underscored(module_path)
          False -> last
        }
      }
    }
  }
}

fn collect_dispatch_type_modules(
  endpoints: List(HandlerEndpoint),
) -> List(String) {
  let from_fields =
    endpoints
    |> list.flat_map(fn(endpoint) {
      endpoint.params
      |> list.flat_map(fn(param) { user_type_modules(param.1) })
    })
  let from_msg_types =
    endpoints
    |> list.filter_map(fn(endpoint) {
      case endpoint.msg_type {
        Some(#(module_path, _)) -> Ok(module_path)
        None -> Error(Nil)
      }
    })
  list.append(from_fields, from_msg_types)
  |> list.unique
  |> list.sort(string.compare)
}

fn user_type_modules(ft: FieldType) -> List(String) {
  case ft {
    UserType(module_path:, args:, ..) -> [
      module_path,
      ..list.flat_map(args, user_type_modules)
    ]
    ListOf(element:) -> user_type_modules(element)
    OptionOf(inner:) -> user_type_modules(inner)
    ResultOf(ok:, err:) ->
      list.append(user_type_modules(ok), user_type_modules(err))
    DictOf(key:, value:) ->
      list.append(user_type_modules(key), user_type_modules(value))
    TupleOf(elements:) -> list.flat_map(elements, user_type_modules)
    _ -> []
  }
}

fn conditional_import(
  endpoints: List(HandlerEndpoint),
  predicate: fn(FieldType) -> Bool,
  import_line: String,
) -> String {
  let needs_import =
    endpoints
    |> list.any(fn(endpoint) {
      endpoint.params
      |> list.any(fn(param) { field_type.contains(param.1, predicate) })
    })
  case needs_import {
    True -> "\n" <> import_line
    False -> ""
  }
}

fn contains_dict(ft: FieldType) -> Bool {
  case ft {
    DictOf(_, _) -> True
    _ -> False
  }
}

fn contains_option(ft: FieldType) -> Bool {
  case ft {
    OptionOf(_) -> True
    _ -> False
  }
}

fn join_imports(imports: List(String)) -> String {
  case imports {
    [] -> ""
    _ -> string.join(imports, "\n") <> "\n"
  }
}

fn duplicates(items: List(String)) -> List(String) {
  items
  |> list.filter(fn(item) {
    items
    |> list.filter(fn(other) { other == item })
    |> list.length
    |> fn(count) { count > 1 }
  })
  |> list.unique
}

fn handler_alias(module_path: String) -> String {
  module_to_underscored(module_path) <> "_handler"
}

fn unused_param_name(name: String, endpoints: List(HandlerEndpoint)) -> String {
  case endpoints {
    [] -> "_" <> name
    _ -> name
  }
}

fn module_to_underscored(module_path: String) -> String {
  string.replace(module_path, "/", "_")
}

fn to_pascal_case(value: String) -> String {
  value
  |> string.split("_")
  |> list.map(capitalize)
  |> string.join("")
}

fn capitalize(value: String) -> String {
  case string.to_graphemes(value) {
    [] -> ""
    [first, ..rest] -> string.uppercase(first) <> string.join(rest, "")
  }
}
