//// Page-local load RPC glue generation.
////
//// This module targets the unified-source chase app shape: page-local wire
//// modules own `ServerMsg` and `LoadResult`, while generated glue owns the
//// repetitive request/result envelopes and browser transport callbacks.

import glance
import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import libero/field_type
import libero/glance_type_resolver.{RejectUnsupported}
import simplifile

pub type GeneratedFile {
  GeneratedFile(path: String, content: String)
}

pub type LoadArg {
  LoadArg(label: String, type_ref: String)
}

pub type LoadRpc {
  LoadRpc(
    /// Stable snake_case name used in generated function names.
    name: String,
    /// The route/page module receiving the request frame.
    module_path: String,
    /// Page-local wire module that defines ServerMsg and LoadResult.
    wire_module: String,
    /// ServerMsg constructor used to request the page load.
    request_constructor: String,
    args: List(LoadArg),
  )
}

pub fn discover(src_root src_root: String) -> Result(List(LoadRpc), String) {
  use files <- result.try(walk_directory(src_root))
  files
  |> list.filter(fn(path) { string.ends_with(path, "/wire.gleam") })
  |> list.try_fold([], fn(loads, path) {
    use discovered <- result.try(discover_file(src_root, path))
    Ok(list.append(loads, discovered))
  })
}

pub fn generate(
  loads loads: List(LoadRpc),
  to_client_module to_client_module: String,
  to_server_module to_server_module: String,
) -> List(GeneratedFile) {
  [
    GeneratedFile(
      "src/generated/rally/client_protocol.gleam",
      client_protocol(loads, to_client_module:, to_server_module:),
    ),
    GeneratedFile(
      "src/generated/rally/server_protocol.gleam",
      server_protocol(loads, to_client_module:, to_server_module:),
    ),
    GeneratedFile(
      "src/generated/rally/client_transport.gleam",
      client_transport(loads, to_client_module:, to_server_module:),
    ),
    GeneratedFile(
      "src/generated/rally/hydration.gleam",
      hydration(loads, to_client_module:),
    ),
  ]
}

pub fn client_protocol(
  loads loads: List(LoadRpc),
  to_client_module to_client_module: String,
  to_server_module to_server_module: String,
) -> String {
  "@target(javascript)
import " <> to_client_module <> ".{type ToClient}
@target(javascript)
import " <> to_server_module <> ".{type ToServer}
@target(javascript)
import generated/libero/result.{type ApiLoadError, type ApiSaveError}
@target(javascript)
import generated/libero/to_client_codec
@target(javascript)
import generated/libero/to_server_codec
" <> wire_imports(loads, "@target(javascript)") <> "
@target(javascript)
pub type ServerFrame {
  Response(message: ToClient)
  Push(module: String, message: ToClient)
}

@target(javascript)
pub fn ensure() -> Nil {
  let _ = to_server_codec.ensure()
  to_client_codec.ensure()
}

@target(javascript)
pub fn send(message: ToServer) -> BitArray {
  to_server_codec.encode(message)
}

@target(javascript)
pub fn encode_request(
  request_id request_id: Int,
  module module: String,
  message message: ToServer,
) -> BitArray {
  encode_any(#(request_id, module, message))
}
" <> string.join(list.map(loads, client_encode_request), "\n") <> "
@target(javascript)
pub fn receive(bytes: BitArray) -> Result(ToClient, Nil) {
  to_client_codec.decode(bytes)
}

@target(javascript)
pub fn decode_server_frame(bytes: BitArray) -> Result(ServerFrame, Nil) {
  case bytes {
    <<0, payload:bits>> -> {
      case to_client_codec.decode(payload) {
        Ok(message) -> Ok(Response(message:))
        Error(Nil) -> Error(Nil)
      }
    }
    <<1, payload:bits>> -> {
      case decode_any(payload) {
        Ok(#(module, message)) -> Ok(Push(module:, message:))
        Error(Nil) -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

@target(javascript)
pub fn decode_load_result(
  bytes: BitArray,
) -> Result(#(Int, Result(ToClient, List(ApiLoadError))), Nil) {
  decode_result_envelope(bytes)
}
" <> string.join(list.map(loads, client_decode_load_result), "\n") <> "
@target(javascript)
pub fn decode_save_result(
  bytes: BitArray,
) -> Result(#(Int, Result(ToClient, List(ApiSaveError))), Nil) {
  decode_result_envelope(bytes)
}

@target(javascript)
pub fn decode_result_envelope(bytes: BitArray) -> Result(#(Int, a), Nil) {
  case bytes {
    <<2, payload:bits>> -> decode_any(payload)
    _ -> Error(Nil)
  }
}

@target(javascript)
@external(javascript, \"../libero/codec_ffi.mjs\", \"encode_value\")
fn encode_any(_value: a) -> BitArray {
  panic as \"generated/rally/client_protocol.encode_any external missing\"
}

@target(javascript)
@external(javascript, \"../libero/codec_ffi.mjs\", \"decode_result\")
fn decode_any(_bytes: BitArray) -> Result(a, Nil) {
  panic as \"generated/rally/client_protocol.decode_any external missing\"
}
"
}

pub fn server_protocol(
  loads loads: List(LoadRpc),
  to_client_module to_client_module: String,
  to_server_module to_server_module: String,
) -> String {
  "@target(erlang)
import " <> to_client_module <> ".{type ToClient}
@target(erlang)
import " <> to_server_module <> ".{type ToServer}
@target(erlang)
import generated/libero/result.{type ApiLoadError, type ApiSaveError}
@target(erlang)
import generated/libero/to_client_codec
@target(erlang)
import generated/libero/to_server_codec
" <> wire_imports(loads, "@target(erlang)") <> "
@target(erlang)
pub type ClientRequest {
  ClientRequest(request_id: Int, module: String, message: ToServer)
}
" <> string.join(list.map(loads, server_request_type), "\n") <> "
@target(erlang)
pub fn ensure() -> Nil {
  let _ = to_server_codec.ensure()
  to_client_codec.ensure()
}

@target(erlang)
pub fn decode(bytes: BitArray) -> Result(ToServer, Nil) {
  to_server_codec.decode(bytes)
}

@target(erlang)
pub fn decode_request(bytes: BitArray) -> Result(ClientRequest, Nil) {
  case decode_any(bytes) {
    Ok(#(request_id, module, message)) ->
      Ok(ClientRequest(request_id:, module:, message:))
    _ -> Error(Nil)
  }
}
" <> string.join(list.map(loads, server_decode_request), "\n") <> "
@target(erlang)
pub fn encode(message: ToClient) -> BitArray {
  to_client_codec.encode(message)
}

@target(erlang)
pub fn encode_response(message message: ToClient) -> BitArray {
  let payload = to_client_codec.encode(message)
  <<0, payload:bits>>
}

@target(erlang)
pub fn encode_load_result(
  request_id request_id: Int,
  result result: Result(ToClient, List(ApiLoadError)),
) -> BitArray {
  encode_result_frame(request_id, result)
}
" <> string.join(list.map(loads, server_encode_load_result), "\n") <> "
@target(erlang)
pub fn encode_save_result(
  request_id request_id: Int,
  result result: Result(ToClient, List(ApiSaveError)),
) -> BitArray {
  encode_result_frame(request_id, result)
}

@target(erlang)
fn encode_result_frame(request_id: Int, result: a) -> BitArray {
  let payload = encode_any(#(request_id, result))
  <<2, payload:bits>>
}

@target(erlang)
pub fn encode_push(
  module module: String,
  message message: ToClient,
) -> BitArray {
  let payload = encode_any(#(module, message))
  <<1, payload:bits>>
}

@target(erlang)
@external(erlang, \"to_server_codec_ffi\", \"decode\")
fn decode_any(_bytes: BitArray) -> Result(a, Nil) {
  panic as \"generated/rally/server_protocol.decode_any external missing\"
}

@target(erlang)
@external(erlang, \"to_client_codec_ffi\", \"encode\")
fn encode_any(_value: a) -> BitArray {
  panic as \"generated/rally/server_protocol.encode_any external missing\"
}
"
}

pub fn client_transport(
  loads loads: List(LoadRpc),
  to_client_module to_client_module: String,
  to_server_module to_server_module: String,
) -> String {
  "@target(javascript)
import " <> to_client_module <> ".{type ToClient}
@target(javascript)
import " <> to_server_module <> ".{type ToServer}
@target(javascript)
import generated/rally/client_protocol
@target(javascript)
import generated/libero/result.{type ApiLoadError, type ApiSaveError}
@target(javascript)
import lustre/effect.{type Effect}
" <> wire_imports(loads, "@target(javascript)") <> "
@target(javascript)
pub fn connect(
  url url: String,
  on_frame on_frame: fn(BitArray) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    connect_socket(url, fn(frame) { dispatch(on_frame(frame)) })
  })
}

@target(javascript)
pub fn send(module module: String, message message: ToServer) -> Effect(msg) {
  effect.from(fn(_dispatch) {
    let request_id = next_request_id()
    let frame = client_protocol.encode_request(request_id, module, message)
    send_frame(frame)
  })
}

@target(javascript)
pub fn send_load(
  module module: String,
  message message: ToServer,
  on_result on_result: fn(Result(ToClient, List(ApiLoadError))) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    let request_id = next_request_id()
    let frame = client_protocol.encode_request(request_id, module, message)
    send_load_frame(request_id, frame, on_result, dispatch)
  })
}
" <> string.join(list.map(loads, transport_send_load), "\n") <> "
@target(javascript)
pub fn send_save(
  module module: String,
  message message: ToServer,
  on_result on_result: fn(Result(ToClient, List(ApiSaveError))) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    let request_id = next_request_id()
    let frame = client_protocol.encode_request(request_id, module, message)
    send_save_frame(request_id, frame, on_result, dispatch)
  })
}

@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"connect\")
fn connect_socket(_url: String, _on_frame: fn(BitArray) -> Nil) -> Nil {
  Nil
}

@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"send_frame\")
fn send_frame(_frame: BitArray) -> Nil {
  Nil
}

@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"send_load_frame\")
fn send_load_frame(
  _request_id: Int,
  _frame: BitArray,
  _on_result: fn(Result(ToClient, List(ApiLoadError))) -> msg,
  _dispatch: fn(msg) -> Nil,
) -> Nil {
  Nil
}
" <> string.join(list.map(loads, transport_external), "\n") <> "
@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"send_save_frame\")
fn send_save_frame(
  _request_id: Int,
  _frame: BitArray,
  _on_result: fn(Result(ToClient, List(ApiSaveError))) -> msg,
  _dispatch: fn(msg) -> Nil,
) -> Nil {
  Nil
}

@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"next_request_id\")
fn next_request_id() -> Int {
  0
}
"
}

pub fn hydration(
  loads loads: List(LoadRpc),
  to_client_module to_client_module: String,
) -> String {
  "@target(javascript)
import " <> to_client_module <> ".{type ToClient}
@target(javascript)
import generated/rally/client_protocol
@target(javascript)
import generated/libero/result.{type ApiLoadError}
@target(javascript)
import generated/libero/to_client_codec
@target(javascript)
import generated/rally/browser
@target(javascript)
import gleam/bit_array
@target(javascript)
import gleam/list
@target(javascript)
import gleam/string
" <> wire_imports(loads, "@target(javascript)") <> "
@target(javascript)
pub fn messages() -> Result(List(ToClient), Nil) {
  case browser.take_boot_string(\"hydration\") {
    \"\" -> Error(Nil)
    raw -> decode_all(string.split(raw, \",\"), [])
  }
}
" <> string.join(list.map(loads, hydration_load_result), "\n") <> "
@target(javascript)
fn decode_all(
  encoded: List(String),
  decoded: List(ToClient),
) -> Result(List(ToClient), Nil) {
  case encoded {
    [] -> Ok(list.reverse(decoded))
    [first, ..rest] ->
      case decode_message(first) {
        Ok(message) -> decode_all(rest, [message, ..decoded])
        Error(Nil) -> Error(Nil)
      }
  }
}

@target(javascript)
fn decode_message(encoded: String) -> Result(ToClient, Nil) {
  case bit_array.base64_url_decode(encoded) {
    Ok(bytes) -> to_client_codec.decode(bytes)
    Error(_) -> Error(Nil)
  }
}
" <> string.join(list.map(loads, hydration_decode_result), "\n")
}

fn discover_file(
  src_root: String,
  path: String,
) -> Result(List(LoadRpc), String) {
  use source <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(e) {
      "Cannot read " <> path <> ": " <> simplifile.describe_error(e)
    }),
  )
  let wire_module = module_from_path(src_root, path)
  let module_path = string.drop_end(wire_module, string.length("/wire"))
  discover_source(source, module_path:, wire_module:)
}

fn discover_source(
  source source: String,
  module_path module_path: String,
  wire_module wire_module: String,
) -> Result(List(LoadRpc), String) {
  use ast <- result.try(
    glance.module(source)
    |> result.map_error(fn(_) { "Cannot parse " <> wire_module }),
  )
  use resolver <- result.try(
    glance_type_resolver.resolver_from_imports(ast.imports)
    |> result.map_error(fn(_) { "Cannot resolve imports for " <> wire_module }),
  )
  case has_custom_type(ast.custom_types, "LoadResult") {
    False -> Ok([])
    True -> {
      case
        list.find(ast.custom_types, fn(def) {
          def.definition.name == "ServerMsg"
        })
      {
        Error(Nil) -> Ok([])
        Ok(def) ->
          def.definition.variants
          |> list.filter(fn(variant) { string.ends_with(variant.name, "Load") })
          |> list.try_map(fn(variant) {
            let name =
              variant.name
              |> string.drop_end(string.length("Load"))
              |> to_snake_case
            use args <- result.try(load_args(
              fields: variant.fields,
              resolver: resolver,
              module_path: wire_module,
              variant_name: variant.name,
            ))
            Ok(LoadRpc(
              name:,
              module_path:,
              wire_module:,
              request_constructor: variant.name,
              args:,
            ))
          })
      }
    }
  }
}

fn load_args(
  fields fields: List(glance.VariantField),
  resolver resolver: glance_type_resolver.TypeResolver,
  module_path module_path: String,
  variant_name variant_name: String,
) -> Result(List(LoadArg), String) {
  fields
  |> list.try_map(fn(field) {
    case field {
      glance.LabelledVariantField(label:, item:) -> {
        use type_ <- result.try(
          glance_type_resolver.type_to_field_type(
            type_: item,
            resolver:,
            current_module: module_path,
            policy: RejectUnsupported(module_path <> "." <> variant_name),
          )
          |> result.map_error(fn(_) {
            "Unsupported load argument type in "
            <> module_path
            <> "."
            <> variant_name
          }),
        )
        Ok(LoadArg(label:, type_ref: field_type.to_gleam_source(type_)))
      }
      glance.UnlabelledVariantField(_) ->
        Error(
          "Load constructor fields must be labelled in "
          <> module_path
          <> "."
          <> variant_name,
        )
    }
  })
}

fn walk_directory(path path: String) -> Result(List(String), String) {
  use entries <- result.try(
    simplifile.read_directory(path)
    |> result.map_error(fn(e) {
      "Failed to read directory "
      <> path
      <> ": "
      <> simplifile.describe_error(e)
    }),
  )
  entries
  |> list.sort(string.compare)
  |> list.try_fold([], fn(acc, entry) {
    let child = path <> "/" <> entry
    let is_dir = simplifile.is_directory(child) |> result.unwrap(False)
    case is_dir {
      True -> {
        use <- bool.guard(when: entry == "generated", return: Ok(acc))
        use nested <- result.try(walk_directory(child))
        Ok(list.append(acc, nested))
      }
      False -> {
        case string.ends_with(child, ".gleam") {
          True -> Ok(list.append(acc, [child]))
          False -> Ok(acc)
        }
      }
    }
  })
}

fn module_from_path(src_root: String, path: String) -> String {
  let prefix = src_root <> "/"
  path
  |> string.drop_start(string.length(prefix))
  |> string.drop_end(string.length(".gleam"))
}

fn wire_imports(loads: List(LoadRpc), target: String) -> String {
  loads
  |> list.map(fn(load) {
    target <> "\nimport " <> load.wire_module <> " as " <> wire_alias(load)
  })
  |> list.unique
  |> string.join("\n")
  |> fn(imports) {
    case imports {
      "" -> ""
      _ -> imports <> "\n"
    }
  }
}

fn wire_alias(load: LoadRpc) -> String {
  load.name <> "_wire"
}

fn pascal_name(load: LoadRpc) -> String {
  load.name
  |> string.split("_")
  |> list.map(fn(word) {
    case string.pop_grapheme(word) {
      Ok(#(first, rest)) -> string.uppercase(first) <> rest
      Error(Nil) -> word
    }
  })
  |> string.join("")
}

fn arg_signature(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) {
    "\n  " <> arg.label <> " " <> arg.label <> ": " <> arg.type_ref <> ","
  })
  |> string.join("")
}

fn arg_labels(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) { arg.label <> ":" })
  |> string.join(", ")
}

fn call_args(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) { arg.label })
  |> string.join(", ")
}

fn constructor(load: LoadRpc) -> String {
  case load.args {
    [] -> wire_alias(load) <> "." <> load.request_constructor
    args ->
      wire_alias(load)
      <> "."
      <> load.request_constructor
      <> "("
      <> arg_labels(args)
      <> ")"
  }
}

fn client_encode_request(load: LoadRpc) -> String {
  "@target(javascript)
pub fn encode_" <> load.name <> "_request(
  request_id request_id: Int," <> arg_signature(load.args) <> "
) -> BitArray {
  encode_any(#(
    request_id,
    \"" <> load.module_path <> "\",
    " <> constructor(load) <> ",
  ))
}
"
}

fn client_decode_load_result(load: LoadRpc) -> String {
  "@target(javascript)
pub fn decode_" <> load.name <> "_load_result(
  bytes: BitArray,
) -> Result(
  #(Int, Result(" <> wire_alias(load) <> ".LoadResult, List(ApiLoadError))),
  Nil,
) {
  decode_result_envelope(bytes)
}
"
}

fn server_request_type(load: LoadRpc) -> String {
  "@target(erlang)
pub type " <> pascal_name(load) <> "ClientRequest {
  " <> pascal_name(load) <> "ClientRequest(
    request_id: Int,
    module: String,
    message: " <> wire_alias(load) <> ".ServerMsg,
  )
}
"
}

fn server_decode_request(load: LoadRpc) -> String {
  "@target(erlang)
pub fn decode_" <> load.name <> "_request(
  bytes: BitArray,
) -> Result(" <> pascal_name(load) <> "ClientRequest, Nil) {
  case decode_any(bytes) {
    Ok(#(request_id, module, message)) ->
      Ok(" <> pascal_name(load) <> "ClientRequest(request_id:, module:, message:))
    _ -> Error(Nil)
  }
}
"
}

fn server_encode_load_result(load: LoadRpc) -> String {
  "@target(erlang)
pub fn encode_" <> load.name <> "_load_result(
  request_id request_id: Int,
  result result: Result(" <> wire_alias(load) <> ".LoadResult, List(ApiLoadError)),
) -> BitArray {
  encode_result_frame(request_id, result)
}
"
}

fn transport_send_load(load: LoadRpc) -> String {
  "@target(javascript)
pub fn send_" <> load.name <> "_load(" <> arg_signature(load.args) <> "
  on_result on_result: fn(
    Result(" <> wire_alias(load) <> ".LoadResult, List(ApiLoadError)),
  ) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    let request_id = next_request_id()
    let frame = client_protocol.encode_" <> load.name <> "_request(request_id" <> case
    load.args
  {
    [] -> ""
    args -> ", " <> call_args(args)
  } <> ")
    send_" <> load.name <> "_load_frame(request_id, frame, on_result, dispatch)
  })
}
"
}

fn transport_external(load: LoadRpc) -> String {
  "@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"send_load_frame\")
fn send_" <> load.name <> "_load_frame(
  _request_id: Int,
  _frame: BitArray,
  _on_result: fn(Result(" <> wire_alias(load) <> ".LoadResult, List(ApiLoadError))) -> msg,
  _dispatch: fn(msg) -> Nil,
) -> Nil {
  Nil
}
"
}

fn hydration_load_result(load: LoadRpc) -> String {
  "@target(javascript)
pub fn " <> load.name <> "_load_result() -> Result(
  Result(" <> wire_alias(load) <> ".LoadResult, List(ApiLoadError)),
  Nil,
) {
  case browser.take_boot_string(\"hydration\") {
    \"\" -> Error(Nil)
    raw ->
      case string.split(raw, \",\") {
        [encoded, ..] -> decode_" <> load.name <> "_load_result(encoded)
        [] -> Error(Nil)
      }
  }
}
"
}

fn hydration_decode_result(load: LoadRpc) -> String {
  "@target(javascript)
fn decode_" <> load.name <> "_load_result(
  encoded: String,
) -> Result(Result(" <> wire_alias(load) <> ".LoadResult, List(ApiLoadError)), Nil) {
  case bit_array.base64_url_decode(encoded) {
    Ok(bytes) ->
      case client_protocol.decode_" <> load.name <> "_load_result(bytes) {
        Ok(#(_, result)) -> Ok(result)
        Error(Nil) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}
"
}

fn has_custom_type(
  custom_types: List(glance.Definition(glance.CustomType)),
  name: String,
) -> Bool {
  list.any(custom_types, fn(def) { def.definition.name == name })
}

fn to_snake_case(name: String) -> String {
  case string.to_graphemes(name) {
    [] -> ""
    [first, ..rest] -> to_snake_case_loop(rest, string.lowercase(first))
  }
}

fn to_snake_case_loop(chars: List(String), acc: String) -> String {
  case chars {
    [] -> acc
    [char, ..rest] -> {
      let lower = string.lowercase(char)
      let prefix = case char != lower && acc != "" {
        True -> "_"
        False -> ""
      }
      to_snake_case_loop(rest, acc <> prefix <> lower)
    }
  }
}
