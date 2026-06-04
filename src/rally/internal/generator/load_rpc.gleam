//// Page-local load RPC glue generation.
////
//// This module targets the unified-source chase app shape: page-local wire
//// modules own `ServerMsg` and `LoadResult`, while generated glue owns the
//// repetitive request/result envelopes and browser transport callbacks.

import glance
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
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
    /// False when the contract lives in the page module, because importing the
    /// page from client transport would create a cycle.
    import_on_client: Bool,
    /// ServerMsg constructor used to request the page load.
    request_constructor: String,
    args: List(LoadArg),
    save_result_type: Option(String),
  )
}

pub fn discover(src_root src_root: String) -> Result(List(LoadRpc), String) {
  use files <- result.try(walk_directory(path: src_root))
  files
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
      client_protocol(loads:, to_client_module:, to_server_module:),
    ),
    GeneratedFile(
      "src/generated/rally/server_protocol.gleam",
      server_protocol(loads:, to_client_module:, to_server_module:),
    ),
    GeneratedFile(
      "src/generated/rally/client_transport.gleam",
      client_transport(loads:, to_client_module:, to_server_module:),
    ),
    GeneratedFile(
      "src/generated/rally/server.gleam",
      page_server(loads:, to_client_module:, to_server_module:),
    ),
    GeneratedFile(
      "src/generated/rally/server_ws.gleam",
      server_ws(loads:, to_client_module:, to_server_module:),
    ),
    GeneratedFile(
      "src/generated/rally/hydration.gleam",
      hydration(loads:, to_client_module:),
    ),
    GeneratedFile("src/generated/rally/result.gleam", result_module()),
  ]
}

pub fn libero_type_seeds(
  loads loads: List(LoadRpc),
) -> List(#(String, String)) {
  let load_seeds =
    loads
    |> list.flat_map(fn(load) {
      let save_seeds = case load.save_result_type {
        Some(type_name) -> [#(load.wire_module, type_name)]
        None -> []
      }
      [
        #(load.wire_module, "ServerMsg"),
        #(load.wire_module, "LoadResult"),
        ..save_seeds
      ]
    })

  [#("broadcasts", "Event"), ..load_seeds]
  |> list.unique
}

pub fn result_module() -> String {
  "import gleam/option.{type Option}

pub type ApiLoadError {
  ApiLoadError(message: String)
}

pub type ApiSaveError {
  ApiSaveError(field: Option(String), message: String)
}
"
}

pub fn client_protocol(
  loads loads: List(LoadRpc),
  to_client_module _to_client_module: String,
  to_server_module _to_server_module: String,
) -> String {
  "@target(javascript)
import generated/rally/result.{type ApiLoadError, type ApiSaveError}
@target(javascript)
import generated/libero/etf as libero_etf
" <> wire_imports(loads, "@target(javascript)", client_only: True) <> "
@target(javascript)
import broadcasts

@target(javascript)
pub type ServerFrame {
  Push(module: String, message: broadcasts.Event)
}

" <> string.join(list.map(loads, client_encode_request), "\n") <> "
@target(javascript)
pub fn decode_server_frame(bytes: BitArray) -> Result(ServerFrame, Nil) {
  case bytes {
    <<1, payload:bits>> -> {
      case decode_any(payload) {
        Ok(#(module, message)) -> Ok(Push(module:, message:))
        Error(Nil) -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

" <> string.join(list.map(loads, client_decode_load_result), "\n") <> "
" <> string.join(
    option.values(list.map(loads, client_decode_save_result)),
    "\n",
  ) <> "

@target(javascript)
pub fn decode_result_envelope(bytes: BitArray) -> Result(#(Int, a), Nil) {
  case bytes {
    <<2, payload:bits>> -> decode_any(payload)
    _ -> Error(Nil)
  }
}

@target(javascript)
fn encode_any(value: a) -> BitArray {
  libero_etf.encode(value)
}

@target(javascript)
fn decode_any(bytes: BitArray) -> Result(a, Nil) {
  case libero_etf.decode(bytes) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}
"
}

pub fn server_protocol(
  loads loads: List(LoadRpc),
  to_client_module _to_client_module: String,
  to_server_module _to_server_module: String,
) -> String {
  "@target(erlang)
import generated/rally/result.{type ApiLoadError, type ApiSaveError}
@target(erlang)
import generated/libero/etf as libero_etf
" <> wire_imports(loads, "@target(erlang)", client_only: False) <> "
@target(erlang)
import broadcasts

@target(erlang)
pub fn ensure() -> Nil {
  libero_etf.ensure()
}

" <> string.join(list.map(loads, server_request_type), "\n") <> "
" <> string.join(list.map(loads, server_decode_request), "\n") <> "
" <> string.join(list.map(loads, server_encode_load_result), "\n") <> "
" <> string.join(
    option.values(list.map(loads, server_encode_save_result)),
    "\n",
  ) <> "
" <> string.join(list.map(loads, server_load_result_encoder), "\n") <> "
" <> string.join(
    option.values(list.map(loads, server_save_result_encoder)),
    "\n",
  ) <> "

@target(erlang)
@external(erlang, \"generated@rpc_wire\", \"encode_broadcasts__event\")
fn encode_push_payload(_message: broadcasts.Event) -> a {
  panic as \"generated/rally/server_protocol.encode_push_payload external missing\"
}

@target(erlang)
fn encode_result_frame(request_id: Int, result: a) -> BitArray {
  let payload = encode_any(#(request_id, result))
  <<2, payload:bits>>
}

@target(erlang)
pub fn encode_push(
  module module: String,
  message message: broadcasts.Event,
) -> BitArray {
  let payload = encode_any(#(module, encode_push_payload(message)))
  <<1, payload:bits>>
}

@target(erlang)
fn encode_ok_payload(result: Result(a, b), encode_ok: fn(a) -> c) -> Result(c, b) {
  case result {
    Ok(payload) -> Ok(encode_ok(payload))
    Error(error) -> Error(error)
  }
}

@target(erlang)
fn decode_any(bytes: BitArray) -> Result(a, Nil) {
  case libero_etf.decode(bytes) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}

@target(erlang)
fn encode_any(value: a) -> BitArray {
  libero_etf.encode(value)
}
"
}

pub fn client_transport(
  loads loads: List(LoadRpc),
  to_client_module _to_client_module: String,
  to_server_module _to_server_module: String,
) -> String {
  "@target(javascript)
import generated/rally/client_protocol
@target(javascript)
import generated/rally/result.{type ApiLoadError, type ApiSaveError}
@target(javascript)
import lustre/effect.{type Effect}
" <> wire_imports(loads, "@target(javascript)", client_only: True) <> "
@target(javascript)
pub fn connect(
  url url: String,
  on_frame on_frame: fn(BitArray) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    connect_socket(url, fn(frame) { dispatch(on_frame(frame)) })
  })
}

" <> string.join(list.map(loads, transport_send_load), "\n") <> "
" <> string.join(option.values(list.map(loads, transport_send_save)), "\n") <> "

@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"connect\")
fn connect_socket(_url: String, _on_frame: fn(BitArray) -> Nil) -> Nil {
  Nil
}

" <> string.join(list.map(loads, transport_external), "\n") <> "
" <> string.join(option.values(list.map(loads, transport_save_external)), "\n") <> "

@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"next_request_id\")
fn next_request_id() -> Int {
  0
}
"
}

pub fn page_server(
  loads loads: List(LoadRpc),
  to_client_module _to_client_module: String,
  to_server_module _to_server_module: String,
) -> String {
  "@target(javascript)
import generated/rally/client_transport
@target(javascript)
import generated/rally/result as transport_result
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option}
@target(javascript)
import lustre/effect.{type Effect}
" <> wire_imports(loads, "@target(javascript)", client_only: True) <> "
@target(erlang)
pub fn ensure() -> Nil {
  Nil
}

@target(javascript)
pub type LoadError {
  LoadError(message: String)
}

@target(javascript)
pub type SaveError {
  SaveError(field: Option(String), message: String)
}

" <> string.join(list.map(loads, page_server_load), "\n") <> "
" <> string.join(option.values(list.map(loads, page_server_save)), "\n") <> "

@target(javascript)
fn map_load_result(
  result: Result(a, List(transport_result.ApiLoadError)),
) -> Result(a, List(LoadError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(list.map(errors, fn(error) {
      let transport_result.ApiLoadError(message:) = error
      LoadError(message:)
    }))
  }
}

@target(javascript)
fn map_save_result(
  result: Result(a, List(transport_result.ApiSaveError)),
) -> Result(a, List(SaveError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(list.map(errors, fn(error) {
      let transport_result.ApiSaveError(field:, message:) = error
      SaveError(field:, message:)
    }))
  }
}
"
}

pub fn server_ws(
  loads loads: List(LoadRpc),
  to_client_module _to_client_module: String,
  to_server_module _to_server_module: String,
) -> String {
  "@target(erlang)
import generated/rally/result as transport_result
@target(erlang)
import generated/rally/server_protocol
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option}
@target(erlang)
import mist.{type WebsocketConnection}
" <> wire_imports(loads, "@target(erlang)", client_only: False) <> "
@target(erlang)
pub type LoadError {
  LoadError(message: String)
}

@target(erlang)
pub type SaveError {
  SaveError(field: Option(String), message: String)
}

@target(erlang)
pub type Handlers(state) {
  Handlers(
" <> server_ws_handler_fields(loads) <> "
  )
}

@target(erlang)
pub fn handle_client_frame(
  state state: state,
  conn conn: WebsocketConnection,
  data data: BitArray,
  handlers handlers: Handlers(state),
) -> Nil {
  server_protocol.ensure()
  " <> server_ws_dispatch_cases(loads) <> "
}

" <> string.join(list.map(loads, server_ws_try_request), "\n") <> "
" <> string.join(list.map(loads, server_ws_send_load_result), "\n") <> "
" <> string.join(
    option.values(list.map(loads, server_ws_send_save_result)),
    "\n",
  ) <> "

@target(erlang)
fn map_load_result(
  result: Result(a, List(LoadError)),
) -> Result(a, List(transport_result.ApiLoadError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(list.map(errors, fn(error) {
      let LoadError(message:) = error
      transport_result.ApiLoadError(message:)
    }))
  }
}

@target(erlang)
fn map_save_result(
  result: Result(a, List(SaveError)),
) -> Result(a, List(transport_result.ApiSaveError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(list.map(errors, fn(error) {
      let SaveError(field:, message:) = error
      transport_result.ApiSaveError(field:, message:)
    }))
  }
}
"
}

pub fn hydration(
  loads loads: List(LoadRpc),
  to_client_module _to_client_module: String,
) -> String {
  "@target(javascript)
import generated/rally/client_protocol
@target(javascript)
import generated/rally/result.{type ApiLoadError}
@target(javascript)
import generated/rally/browser
@target(javascript)
import gleam/bit_array
@target(javascript)
import gleam/string
" <> wire_imports(loads, "@target(javascript)", client_only: True) <> "
" <> string.join(list.map(loads, hydration_load_result), "\n") <> "
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
  let source_module = module_from_path(src_root, path)
  let is_wire = string.ends_with(source_module, "/wire")
  let module_path = case is_wire {
    True -> string.drop_end(source_module, string.length("/wire"))
    False -> source_module
  }
  discover_source(
    source:,
    module_path:,
    wire_module: source_module,
    import_on_client: is_wire,
  )
}

fn discover_source(
  source source: String,
  module_path module_path: String,
  wire_module wire_module: String,
  import_on_client import_on_client: Bool,
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
      let save_result_type = case
        import_on_client,
        has_custom_type(ast.custom_types, "GameUpdate")
      {
        False, True -> Some("GameUpdate")
        _, _ -> None
      }
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
              import_on_client:,
              request_constructor: variant.name,
              args:,
              save_result_type:,
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
        use nested <- result.try(walk_directory(path: child))
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

fn wire_imports(
  loads: List(LoadRpc),
  target: String,
  client_only client_only: Bool,
) -> String {
  loads
  |> list.filter(fn(load) { !client_only || load.import_on_client })
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
  case load.import_on_client, load.args {
    False, _ -> "message"
    True, [] -> wire_alias(load) <> "." <> load.request_constructor
    True, args ->
      wire_alias(load)
      <> "."
      <> load.request_constructor
      <> "("
      <> arg_labels(args)
      <> ")"
  }
}

fn client_encode_request(load: LoadRpc) -> String {
  let signature = case load.import_on_client {
    True -> arg_signature(load.args)
    False -> "\n  message message: a,"
  }

  "@target(javascript)
pub fn encode_" <> load.name <> "_request(
  request_id request_id: Int," <> signature <> "
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
  #(Int, Result(" <> client_load_result_type(load) <> ", List(ApiLoadError))),
  Nil,
) {
  decode_result_envelope(bytes)
}
"
}

fn client_decode_save_result(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(javascript)
pub fn decode_" <> load.name <> "_save_result(
  bytes: BitArray,
) -> Result(#(Int, Result(" <> client_save_result_type(load) <> ", List(ApiSaveError))), Nil) {
  decode_result_envelope(bytes)
}
")
  }
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
  encode_result_frame(request_id, encode_" <> load.name <> "_load_result_payload(result))
}
"
}

fn server_encode_save_result(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(save_result_type) -> Some("@target(erlang)
pub fn encode_" <> load.name <> "_save_result(
  request_id request_id: Int,
  result result: Result(" <> wire_alias(load) <> "." <> save_result_type <> ", List(ApiSaveError)),
) -> BitArray {
  encode_result_frame(request_id, encode_" <> load.name <> "_save_result_payload(result))
}
")
  }
}

fn server_load_result_encoder(load: LoadRpc) -> String {
  "@target(erlang)
fn encode_" <> load.name <> "_load_result_payload(
  result: Result(" <> wire_alias(load) <> ".LoadResult, List(ApiLoadError)),
) -> Result(a, List(ApiLoadError)) {
  encode_ok_payload(result, encode_" <> load.name <> "_load_result_value)
}

@target(erlang)
@external(erlang, \"generated@rpc_wire\", \"" <> wire_encoder_function(
    load.wire_module,
    "LoadResult",
  ) <> "\")
fn encode_" <> load.name <> "_load_result_value(
  _value: " <> wire_alias(load) <> ".LoadResult,
) -> a {
  panic as \"generated/rally/server_protocol.encode_" <> load.name <> "_load_result_value external missing\"
}
"
}

fn server_save_result_encoder(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(save_result_type) -> Some("@target(erlang)
fn encode_" <> load.name <> "_save_result_payload(
  result: Result(" <> wire_alias(load) <> "." <> save_result_type <> ", List(ApiSaveError)),
) -> Result(a, List(ApiSaveError)) {
  encode_ok_payload(result, encode_" <> load.name <> "_save_result_value)
}

@target(erlang)
@external(erlang, \"generated@rpc_wire\", \"" <> wire_encoder_function(
        load.wire_module,
        save_result_type,
      ) <> "\")
fn encode_" <> load.name <> "_save_result_value(
  _value: " <> wire_alias(load) <> "." <> save_result_type <> ",
) -> a {
  panic as \"generated/rally/server_protocol.encode_" <> load.name <> "_save_result_value external missing\"
}
")
  }
}

fn transport_send_load(load: LoadRpc) -> String {
  let signature = case load.import_on_client {
    True -> arg_signature(load.args)
    False -> "\n  message message: a,"
  }
  let call_args = case load.import_on_client, load.args {
    False, _ -> ", message"
    True, [] -> ""
    True, args -> ", " <> call_args(args)
  }

  "@target(javascript)
pub fn send_" <> load.name <> "_load(" <> signature <> "
  on_result on_result: fn(
    Result(" <> client_load_result_type(load) <> ", List(ApiLoadError)),
  ) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    let request_id = next_request_id()
    let frame = client_protocol.encode_" <> load.name <> "_request(request_id" <> call_args <> ")
    send_" <> load.name <> "_load_frame(request_id, frame, on_result, dispatch)
  })
}
"
}

fn transport_send_save(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(javascript)
pub fn send_" <> load.name <> "_save(
  message message: a,
  on_result on_result: fn(Result(" <> client_save_result_type(load) <> ", List(ApiSaveError))) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    let request_id = next_request_id()
    let frame = client_protocol.encode_" <> load.name <> "_request(request_id, message)
    send_" <> load.name <> "_save_frame(request_id, frame, on_result, dispatch)
  })
}
")
  }
}

fn transport_external(load: LoadRpc) -> String {
  "@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"send_load_frame\")
fn send_" <> load.name <> "_load_frame(
  _request_id: Int,
  _frame: BitArray,
  _on_result: fn(Result(" <> client_load_result_type(load) <> ", List(ApiLoadError))) -> msg,
  _dispatch: fn(msg) -> Nil,
) -> Nil {
  Nil
}
"
}

fn transport_save_external(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"send_save_frame\")
fn send_" <> load.name <> "_save_frame(
  _request_id: Int,
  _frame: BitArray,
  _on_result: fn(Result(" <> client_save_result_type(load) <> ", List(ApiSaveError))) -> msg,
  _dispatch: fn(msg) -> Nil,
) -> Nil {
  Nil
}
")
  }
}

fn page_server_load(load: LoadRpc) -> String {
  let signature = case load.import_on_client {
    True -> arg_signature(load.args)
    False -> "\n  message message: a,"
  }
  let call_args = case load.import_on_client, load.args {
    False, _ -> "message: message, "
    True, [] -> ""
    True, args -> arg_labels(args) <> ", "
  }

  "@target(javascript)
pub fn load_" <> load.name <> "(" <> signature <> "
  on_result on_result: fn(
    Result(" <> client_load_result_type(load) <> ", List(LoadError)),
  ) -> msg,
) -> Effect(msg) {
  client_transport.send_" <> load.name <> "_load(
    " <> call_args <> "on_result: fn(result) {
      on_result(map_load_result(result))
    },
  )
}
"
}

fn page_server_save(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(javascript)
pub fn save_" <> load.name <> "(
  message message: a,
  on_result on_result: fn(Result(" <> client_save_result_type(load) <> ", List(SaveError))) -> msg,
) -> Effect(msg) {
  client_transport.send_" <> load.name <> "_save(
    message: message,
    on_result: fn(result) {
      on_result(map_save_result(result))
    },
  )
}
")
  }
}

fn server_ws_handler_fields(loads: List(LoadRpc)) -> String {
  let load_fields = list.map(loads, server_ws_load_handler_field)
  let save_fields =
    option.values(list.map(loads, server_ws_save_handler_fields))

  list.append(load_fields, save_fields)
  |> string.join("\n")
}

fn server_ws_load_handler_field(load: LoadRpc) -> String {
  "    "
  <> load.name
  <> "_load: fn("
  <> server_ws_handler_args_type(load)
  <> ") -> Result("
  <> wire_alias(load)
  <> ".LoadResult, List(LoadError)),"
}

fn server_ws_save_handler_fields(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(save_result_type) ->
      Some(
        "    "
        <> load.name
        <> "_save: fn(state, "
        <> wire_alias(load)
        <> ".ServerMsg) -> Result("
        <> wire_alias(load)
        <> "."
        <> save_result_type
        <> ", List(SaveError)),\n"
        <> "    after_"
        <> load.name
        <> "_save: fn(state, "
        <> wire_alias(load)
        <> ".ServerMsg, "
        <> wire_alias(load)
        <> "."
        <> save_result_type
        <> ") -> Nil,",
      )
  }
}

fn server_ws_dispatch_cases(loads: List(LoadRpc)) -> String {
  case loads {
    [] -> "Nil"
    [first, ..rest] -> server_ws_dispatch_case(first, rest)
  }
}

fn server_ws_dispatch_case(load: LoadRpc, rest: List(LoadRpc)) -> String {
  "case try_"
  <> load.name
  <> "_request(state: state, conn: conn, data: data, handlers: handlers) {
    Ok(Nil) -> Nil
    Error(Nil) -> "
  <> server_ws_dispatch_cases(rest)
  <> "
  }"
}

fn server_ws_try_request(load: LoadRpc) -> String {
  "@target(erlang)
fn try_" <> load.name <> "_request(
  state state: state,
  conn conn: WebsocketConnection,
  data data: BitArray,
  handlers handlers: Handlers(state),
) -> Result(Nil, Nil) {
  case server_protocol.decode_" <> load.name <> "_request(data) {
    Ok(server_protocol." <> pascal_name(load) <> "ClientRequest(
      request_id: request_id,
      module: \"" <> load.module_path <> "\",
      message: " <> server_ws_load_pattern(load) <> ",
    )) -> {
      send_" <> load.name <> "_load_result(
        state: state,
        conn: conn,
        request_id: request_id,
        handlers: handlers" <> server_ws_pass_args(load.args) <> ",
      )
      Ok(Nil)
    }
" <> server_ws_try_save_case(load) <> "
    _ -> Error(Nil)
  }
}
"
}

fn server_ws_try_save_case(load: LoadRpc) -> String {
  case load.save_result_type {
    None -> ""
    Some(_) -> "    Ok(server_protocol." <> pascal_name(load) <> "ClientRequest(
      request_id: request_id,
      module: \"" <> load.module_path <> "\",
      message: message,
    )) ->
      case message {
" <> server_ws_module_load_patterns(load) <> "        _ -> {
          send_" <> load.name <> "_save_result(
            state: state,
            conn: conn,
            request_id: request_id,
            message: message,
            handlers: handlers,
          )
          Ok(Nil)
        }
      }
"
  }
}

fn server_ws_send_load_result(load: LoadRpc) -> String {
  "@target(erlang)
fn send_" <> load.name <> "_load_result(
  state state: state,
  conn conn: WebsocketConnection,
  request_id request_id: Int,
  handlers handlers: Handlers(state)" <> server_ws_arg_params(load.args) <> ",
) -> Nil {
  let result =
    handlers." <> load.name <> "_load(" <> server_ws_handler_args_call(load) <> ")
    |> map_load_result

  let _sent =
    mist.send_binary_frame(
      conn,
      server_protocol.encode_" <> load.name <> "_load_result(
        request_id: request_id,
        result: result,
      ),
    )
  Nil
}
"
}

fn server_ws_send_save_result(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(erlang)
fn send_" <> load.name <> "_save_result(
  state state: state,
  conn conn: WebsocketConnection,
  request_id request_id: Int,
  message message: " <> wire_alias(load) <> ".ServerMsg,
  handlers handlers: Handlers(state),
) -> Nil {
  let result = handlers." <> load.name <> "_save(state, message)

  let _sent =
    mist.send_binary_frame(
      conn,
      server_protocol.encode_" <> load.name <> "_save_result(
        request_id: request_id,
        result: map_save_result(result),
      ),
    )

  case result {
    Ok(value) -> handlers.after_" <> load.name <> "_save(state, message, value)
    Error(_) -> Nil
  }
}
")
  }
}

fn server_ws_handler_args_type(load: LoadRpc) -> String {
  let arg_types =
    load.args
    |> list.map(fn(arg) { arg.type_ref })
    |> string.join(", ")

  case arg_types {
    "" -> "state"
    _ -> "state, " <> arg_types
  }
}

fn server_ws_handler_args_call(load: LoadRpc) -> String {
  let args = call_args(load.args)

  case args {
    "" -> "state"
    _ -> "state, " <> args
  }
}

fn server_ws_arg_params(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) {
    ",\n  " <> arg.label <> " " <> arg.label <> ": " <> arg.type_ref
  })
  |> string.join("")
}

fn server_ws_pass_args(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) { ",\n        " <> arg.label <> ": " <> arg.label })
  |> string.join("")
}

fn server_ws_load_pattern(load: LoadRpc) -> String {
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

fn server_ws_module_load_patterns(load: LoadRpc) -> String {
  "        " <> server_ws_load_pattern(load) <> " -> Error(Nil)\n"
}

fn hydration_load_result(load: LoadRpc) -> String {
  "@target(javascript)
pub fn " <> load.name <> "_load_result() -> Result(
  Result(" <> client_load_result_type(load) <> ", List(ApiLoadError)),
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
) -> Result(Result(" <> client_load_result_type(load) <> ", List(ApiLoadError)), Nil) {
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

fn client_load_result_type(load: LoadRpc) -> String {
  use <- bool.guard(when: !load.import_on_client, return: "load_result")
  wire_alias(load) <> ".LoadResult"
}

fn client_save_result_type(load: LoadRpc) -> String {
  case load.import_on_client, load.save_result_type {
    True, Some(save_result_type) -> wire_alias(load) <> "." <> save_result_type
    _, _ -> "save_result"
  }
}

fn wire_encoder_function(module_path: String, type_name: String) -> String {
  "encode_"
  <> string.replace(module_path, "/", "_")
  <> "__"
  <> to_snake_case(type_name)
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
