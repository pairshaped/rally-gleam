//// JSON protocol integration tests.
////
//// This file protects Rally's JSON path across scanner, parser, generators,
//// generated fixtures, JavaScript decode behavior, and Erlang push encoding.
//// It is intentionally broad because JSON protocol work crosses Libero,
//// generated Gleam, generated JS, and runtime transport boundaries.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import libero/field_type as libero_field_type
import libero/scanner.{HandlerEndpoint}
import rally/internal/generator
import rally/internal/generator/codec
import rally/internal/generator/ssr_handler
import rally/internal/generator/ws_handler
import rally/internal/parser
import rally/internal/scanner as rally_scanner
import rally/internal/types.{type ScanConfig, ScanConfig, ScannedRoute}
import simplifile

const fixture_root = "fixtures/json_protocol"

@external(erlang, "libero_ffi", "find_executable")
fn find_executable(name: String) -> Option(String)

@external(erlang, "libero_ffi", "run_executable_capturing")
fn run_executable_capturing_ffi(
  path: String,
  args: List(String),
) -> #(Int, String)

fn run_gleam(cwd: String, args: List(String)) -> #(Int, String) {
  case find_executable("sh"), find_executable("gleam") {
    Some(sh), Some(gleam) -> {
      let command =
        "cd " <> cwd <> " && " <> gleam <> " " <> string.join(args, " ")
      run_executable_capturing_ffi(sh, ["-c", command])
    }
    _, None -> #(-1, "gleam executable not found on PATH")
    None, _ -> #(-1, "sh executable not found on PATH")
  }
}

fn build_client_fixture() {
  let client_dir = fixture_root <> "/.generated_clients/public"
  let #(build_status, build_output) = run_gleam(client_dir, ["build"])
  case build_status {
    0 -> Nil
    _ -> {
      case string.contains(build_output, "build/packages/libero/gleam.toml") {
        True -> clean_and_rebuild_client_fixture(client_dir, build_output)
        False -> {
          let msg = "Client fixture gleam build failed:\n" <> build_output
          panic as msg
        }
      }
    }
  }
}

fn clean_and_rebuild_client_fixture(client_dir: String, first_output: String) {
  let #(clean_status, clean_output) = run_gleam(client_dir, ["clean"])
  case clean_status {
    0 -> {
      let #(build_status, build_output) = run_gleam(client_dir, ["build"])
      case build_status {
        0 -> Nil
        _ -> {
          let msg =
            "Client fixture gleam build failed after cleaning stale packages:\n"
            <> first_output
            <> "\n--- after clean ---\n"
            <> build_output
          panic as msg
        }
      }
    }
    _ -> {
      let msg =
        "Client fixture gleam clean failed after stale package build error:\n"
        <> first_output
        <> "\n--- clean output ---\n"
        <> clean_output
      panic as msg
    }
  }
}

fn json_config() -> ScanConfig {
  ScanConfig(
    pages_root: fixture_root <> "/src/public/pages",
    output_route: "",
    output_dispatch: "",
    output_server_dispatch: "",
    output_server_atoms: "",
    atoms_module: "",
    output_server_wire: "",
    wire_module: "",
    output_ssr: "",
    output_ws: "",
    output_http: "",
    client_root: "",
    route_root: "/",
    rally_package_path: "",
    shell_file: fixture_root <> "/src/public/shell.html",
    server_deps: dict.new(),
    protocol: "json",
  )
}

fn last_module_segment(module_path: String) -> String {
  case string.split_once(module_path, "pages/") {
    Ok(#(_, rest)) -> rest
    Error(_) -> module_path
  }
}

// =============================================================================
// E2E pipeline test
// =============================================================================

pub fn json_wire_e2e_fixture_scan_test() {
  let config = json_config()

  // 1. Scanner discovers route
  let assert Ok(routes) = rally_scanner.scan(config)
  list.length(routes) |> should.equal(2)
  let assert Ok(route) = list.first(routes)
  route.variant_name |> should.equal("Home")
  route.params |> should.equal([])

  // 2. Parser extracts page contract
  let file_path =
    config.pages_root
    <> "/"
    <> last_module_segment(route.module_path)
    <> ".gleam"
  let assert Ok(source) = simplifile.read(file_path)
  let assert Ok(contract) =
    parser.parse_page(source, module_path: route.module_path)
  contract.has_model |> should.be_true()
  contract.has_init |> should.be_true()

  // 3. Generator produces router
  let router_src = generator.generate(routes)
  router_src |> string.contains("pub type Route {") |> should.be_true()
  router_src |> string.contains("Home") |> should.be_true()
  router_src |> string.contains("pub fn parse_route") |> should.be_true()
  router_src |> string.contains("pub fn route_to_path") |> should.be_true()

  // 4. Generator produces dispatch
  let dispatch_src =
    generator.generate_dispatch(
      routes,
      [#(route, contract)],
      False,
      "generated/router",
      "client_context",
    )
  dispatch_src |> string.contains("pub type PageModel") |> should.be_true()
  dispatch_src |> string.contains("pub type PageMsg") |> should.be_true()
  dispatch_src |> string.contains("pub fn init_page") |> should.be_true()
  dispatch_src |> string.contains("NoPageModel") |> should.be_true()
  dispatch_src |> string.contains("NoPageMsg") |> should.be_true()
}

// =============================================================================
// Guard tests
// =============================================================================

pub fn json_wire_protocol_wire_is_json_mode_test() {
  let source =
    generator.generate_protocol_wire(
      "json",
      "generated@rpc_atoms",
      "test_hash_123",
      "generated/rpc_dispatch",
      [],
      None,
      "generated/protocol_wire",
    )
  source |> string.contains("libero/json/wire") |> should.be_true()
  source |> string.contains("libero/wire") |> should.be_false()
}

pub fn json_wire_no_raw_json_in_runtime_test() {
  // WS handler with JSON protocol should not contain raw JS JSON calls
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("JSON.parse") |> should.be_false()
  ws |> string.contains("JSON.stringify") |> should.be_false()

  // SSR handler with JSON protocol should not contain raw JS JSON calls
  let ssr =
    ssr_handler.generate(
      [],
      False,
      False,
      "server_context",
      "generated/router",
      "<html></html>",
      "",
      Some("generated@rpc_wire"),
      None,
      None,
      "generated/protocol_wire",
      "json",
    )
  ssr |> string.contains("JSON.parse") |> should.be_false()
  ssr |> string.contains("JSON.stringify") |> should.be_false()
}

pub fn json_wire_no_byte_tags_in_app_test() {
  // WS handler with JSON protocol should not contain ETF byte tags
  // (0x00, 0x01 are ETF call/response markers from the binary wire protocol)
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("0x00") |> should.be_false()
  ws |> string.contains("0x01") |> should.be_false()

  // SSR handler with JSON protocol should not contain ETF byte tags
  let ssr =
    ssr_handler.generate(
      [],
      False,
      False,
      "server_context",
      "generated/router",
      "<html></html>",
      "",
      Some("generated@rpc_wire"),
      None,
      None,
      "generated/protocol_wire",
      "json",
    )
  ssr |> string.contains("0x00") |> should.be_false()
  ssr |> string.contains("0x01") |> should.be_false()
}

pub fn json_wire_ws_handler_has_text_branch_test() {
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("mist.Text") |> should.be_true()
  // ETF mode uses mist.Binary, JSON adds mist.Text
  ws |> string.contains("mist.Text(_data)") |> should.be_true()
}

pub fn json_wire_ws_handler_reports_malformed_rpc_frames_test() {
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )

  ws |> string.contains("wire.malformed_rpc_result()") |> should.be_true()
  ws
  |> string.contains("wire.send_rpc_result(conn, result)")
  |> should.be_true()
}

pub fn json_wire_ws_handler_no_etf_imports_test() {
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("gleam/bit_array") |> should.be_false()
  ws |> string.contains("gleam/time/duration") |> should.be_true()
  ws |> string.contains("gleam/time/timestamp") |> should.be_true()
  ws |> string.contains("rpc_dispatch") |> should.be_false()
  ws |> string.contains("rally/runtime/internal/system_db") |> should.be_true()
}

pub fn json_wire_ws_handler_auth_has_timestamp_imports_test() {
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      Some(types.AuthConfig(auth_module: "my_app/auth")),
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("gleam/time/duration") |> should.be_true()
  ws |> string.contains("gleam/time/timestamp") |> should.be_true()
  ws |> string.contains("gleam/bit_array") |> should.be_false()
}

pub fn json_wire_protocol_wire_decodes_client_context_messages_test() {
  let source =
    generator.generate_protocol_wire_with_client_context(
      protocol: "json",
      atoms_module: "generated@rpc_atoms",
      contract_hash: "test_hash_123",
      rpc_dispatch_module: "generated/rpc_dispatch",
      endpoints: [],
      auth_config: None,
      wire_import_module: "generated/protocol_wire",
      client_context_module: Some("public/client_context"),
    )

  source
  |> string.contains("pub fn decode_client_context_msg")
  |> should.be_true()
  source
  |> string.contains(
    "json_codecs.json_decode_public_client_context__client_context_msg(value)",
  )
  |> should.be_true()
}

pub fn json_wire_ws_handler_routes_client_context_frames_test() {
  let ws =
    ws_handler.generate_with_client_context(
      page_contracts: [],
      atoms_module: "",
      rpc_dispatch_module: "",
      auth_config: None,
      from_session_module: "server_context",
      endpoints: [],
      wire_import_module: "generated/protocol_wire",
      protocol: "json",
      has_client_context: True,
    )

  ws
  |> string.contains("envelope.module == \"__ClientContext__\"")
  |> should.be_true()
  ws
  |> string.contains("wire.decode_client_context_msg(envelope.message)")
  |> should.be_true()
  ws
  |> string.contains(
    "wire.encode_push(\"__ClientContext__\", client_context_msg)",
  )
  |> should.be_true()
}

pub fn json_wire_protocol_wire_no_unused_alias_test() {
  let source =
    generator.generate_protocol_wire(
      "json",
      "generated@rpc_atoms",
      "test_hash_123",
      "generated/rpc_dispatch",
      [],
      None,
      "generated/protocol_wire",
    )
  source |> string.contains("as json_error") |> should.be_false()
  source |> string.contains("_value: Dynamic") |> should.be_true()
  source |> string.contains("_value: a") |> should.be_true()
}

pub fn json_wire_client_codec_no_json_error_constructor_test() {
  let files =
    codec.generate(
      contracts: [],
      discovered: [],
      endpoints: [],
      server_symbols: [],
      protocol: "json",
    )
  let assert Ok(codec_file) =
    list.find(files, fn(f) { string.contains(f.path, "codec.gleam") })
  codec_file.content
  |> string.contains("type JsonError")
  |> should.be_true()
  codec_file.content
  |> string.contains("{type JsonError, JsonError}")
  |> should.be_false()
}

pub fn json_wire_facade_is_only_wire_import_test() {
  // Generated WS handler should import protocol_wire facade, not libero wire modules
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("libero/wire") |> should.be_false()
  ws |> string.contains("libero/json/wire") |> should.be_false()

  // Generated SSR handler should not import libero wire modules directly
  let ssr =
    ssr_handler.generate(
      [],
      False,
      False,
      "server_context",
      "generated/router",
      "<html></html>",
      "",
      Some("generated@rpc_wire"),
      None,
      None,
      "generated/protocol_wire",
      "json",
    )
  ssr |> string.contains("libero/wire") |> should.be_false()
  ssr |> string.contains("libero/json/wire") |> should.be_false()
}

// =============================================================================
// Compile test — proves the generated JSON WS handler actually compiles
// =============================================================================

// =============================================================================
// Fixture compile gate — JSON protocol app must build clean
// =============================================================================

pub fn json_fixture_builds_test() {
  // Run rally gen first to ensure generated code matches current generator
  let #(gen_status, gen_output) =
    run_gleam(fixture_root, ["run", "-m", "rally", "--", "gen"])
  let gen_msg =
    "Fixture rally gen failed (exit "
    <> int.to_string(gen_status)
    <> "):\n"
    <> gen_output
  case gen_status {
    0 -> Nil
    _ -> panic as gen_msg
  }

  // Now build
  let #(build_status, build_output) = run_gleam(fixture_root, ["build"])
  let build_msg =
    "Fixture gleam build failed (exit "
    <> int.to_string(build_status)
    <> "):\n"
    <> build_output
  case build_status {
    0 -> Nil
    _ -> panic as build_msg
  }
}

pub fn json_http_fixture_dispatches_real_request_test() {
  let #(gen_status, gen_output) =
    run_gleam(fixture_root, ["run", "-m", "rally", "--", "gen"])
  let gen_msg =
    "Fixture rally gen failed (exit "
    <> int.to_string(gen_status)
    <> "):\n"
    <> gen_output
  case gen_status {
    0 -> Nil
    _ -> panic as gen_msg
  }

  let #(probe_status, probe_output) =
    run_gleam(fixture_root, ["run", "-m", "json_http_probe"])
  let probe_msg =
    "JSON HTTP probe failed (exit "
    <> int.to_string(probe_status)
    <> "):\n"
    <> probe_output
  case probe_status {
    0 -> Nil
    _ -> panic as probe_msg
  }
}

// =============================================================================
// Identity collision tests — prove the protocol preserves type identity
// =============================================================================

pub fn json_wire_identity_distinct_modules_test() {
  // Two handlers with the same type name (Discount) in different modules
  // must emit distinct fully-qualified "type" values.
  let ep1 =
    HandlerEndpoint(
      module_path: "admin/dashboard/discount",
      fn_name: "create",
      return_ok: libero_field_type.IntField,
      return_err: libero_field_type.NilField,
      params: [#("id", libero_field_type.IntField)],
      mutates_context: False,
      msg_type: Some(#("admin/dashboard/discount", "Discount")),
    )
  let ep2 =
    HandlerEndpoint(
      module_path: "admin/discounts/discount",
      fn_name: "create",
      return_ok: libero_field_type.IntField,
      return_err: libero_field_type.NilField,
      params: [
        #("code", libero_field_type.StringField),
        #("cents", libero_field_type.IntField),
      ],
      mutates_context: False,
      msg_type: Some(#("admin/discounts/discount", "Discount")),
    )

  let wire =
    generator.generate_protocol_wire(
      "json",
      "generated@rpc_atoms",
      "test_hash",
      "generated/rpc_dispatch",
      [ep1, ep2],
      None,
      "generated/protocol_wire",
    )

  // Both must appear with their distinct type identities
  wire
  |> string.contains("\"admin/dashboard/discount.Discount\"")
  |> should.be_true()
  wire
  |> string.contains("\"admin/discounts/discount.Discount\"")
  |> should.be_true()
  // Neither must match by variant name alone
  wire
  |> string.contains("Ok(\"Discount\") -> {")
  |> should.be_false()
}

pub fn json_wire_server_dispatch_uses_qualified_types_test() {
  // Server dispatch must match on fully qualified type, not bare variant name.
  let endpoint =
    HandlerEndpoint(
      module_path: "admin/dashboard/discount",
      fn_name: "create",
      return_ok: libero_field_type.IntField,
      return_err: libero_field_type.NilField,
      params: [#("id", libero_field_type.IntField)],
      mutates_context: False,
      msg_type: Some(#("admin/dashboard/discount", "Discount")),
    )

  let wire =
    generator.generate_protocol_wire(
      "json",
      "generated@rpc_atoms",
      "test_hash",
      "generated/rpc_dispatch",
      [endpoint],
      None,
      "generated/protocol_wire",
    )

  wire
  |> string.contains("Ok(\"admin/dashboard/discount.Discount\") -> {")
  |> should.be_true()
}

pub fn json_wire_client_encoder_uses_qualified_types_test() {
  // json_encode_client_msg must emit fully qualified type names
  // (not bare variant names) in the "type" field of the Libero
  // typed-value shape. This test goes through codec.generate to
  // verify the generated client types.gleam content.
  let endpoint =
    HandlerEndpoint(
      module_path: "admin/dashboard/discount",
      fn_name: "create",
      return_ok: libero_field_type.IntField,
      return_err: libero_field_type.NilField,
      params: [#("id", libero_field_type.IntField)],
      mutates_context: False,
      msg_type: Some(#("admin/dashboard/discount", "Discount")),
    )

  // Minimal contract so codec.generate can produce page modules
  let route =
    ScannedRoute(
      segments: [],
      variant_name: "DashboardDiscount",
      params: [],
      layout_module: None,
      module_path: "admin/dashboard/discount",
    )
  let contract =
    parser.parse_page(
      "pub type Msg { Increment } pub type Model { Model } pub fn init() { #(Model, effect.none()) } pub fn update(m, _) { #(m, effect.none()) } pub fn view(_) { html.div([], []) }",
      module_path: "admin/dashboard/discount",
    )
  let assert Ok(contract) = contract

  let files =
    codec.generate(
      contracts: [#(route, contract)],
      discovered: [],
      endpoints: [endpoint],
      server_symbols: [],
      protocol: "json",
    )
  let assert Ok(types_file) =
    list.find(files, fn(f) { f.path == "src/generated/types.gleam" })

  // Must use the fully qualified type name, not bare variant
  let content = types_file.content
  content
  |> string.contains("\"admin/dashboard/discount.Discount\"")
  |> should.be_true()
  // Must NOT match by bare variant name alone
  content
  |> string.contains("#(\"type\", json.string(\"Discount\"))")
  |> should.be_false()
}

pub fn json_wire_js_decode_reconstructs_correct_core_types_test() {
  // Result and Option types must be decoded with correct wire shapes.
  let js = generator.generate_protocol_wire_js("json", "test_hash_abc123")

  // Result types use array fields (matching Libero's wire format)
  js
  |> string.contains("Array.isArray(f) ? f[0]")
  |> should.be_true()
  // Option types handle both array and empty-object fields
  js
  |> string.contains("Array.isArray(f) && f.length === 0")
  |> should.be_true()
}

// RED: This test will fail until client JSON decode routes through
// generated typed constructors keyed by full type identity, instead
// of generic `new CustomType(v, fields)`.
//
// When the identity fix lands, this test should assert the absence
// of `new CustomType(v, fields)` and the presence of a generated
// constructor registry that dispatches by the full "type" field
// (e.g. "public/pages/home_.IncrementResult" → SpecificConstructor).
pub fn red_json_wire_js_decode_must_not_use_generic_custom_type_test() {
  let js = generator.generate_protocol_wire_js("json", "test_hash_abc123")

  // Once typed constructors land, this must be false:
  // the decode path must NOT rely on generic CustomType reconstruction
  // that discards the module-qualified source identity.
  js |> string.contains("new CustomType(v, fields)") |> should.be_false()
}

pub fn json_wire_js_decode_imports_type_registry_test() {
  let js = generator.generate_protocol_wire_js("json", "test_hash_abc123")

  // protocol_wire.mjs must import the generated type registry
  js
  |> string.contains("import { typeRegistry } from \"./type_registry.mjs\"")
  |> should.be_true()
}

pub fn json_wire_js_decode_uses_registry_lookup_test() {
  let js = generator.generate_protocol_wire_js("json", "test_hash_abc123")

  // The decode path must use typeRegistry for user types
  js |> string.contains("const ctor = typeRegistry[key]") |> should.be_true()

  // Must dispatch by full "type" + "#" + "variant" identity
  // so mismatched parent type ("OldType" with variant "Discount")
  // never resolves to a "Discount" type entry.
  js
  |> string.contains("const key = t + \"#\" + v")
  |> should.be_true()

  // Must pass decoded fields to the looked-up constructor
  js |> string.contains("return ctor(fields)") |> should.be_true()
}

pub fn json_wire_js_decode_fails_loudly_on_unknown_type_test() {
  let js = generator.generate_protocol_wire_js("json", "test_hash_abc123")

  // Unknown types must throw, not silently fall back to generic CustomType
  js
  |> string.contains(
    "throw new Error(\"Unknown type in JSON decode: type=\" + t + \" variant=\" + v",
  )
  |> should.be_true()
}

pub fn json_wire_js_response_decode_error_preserves_request_id_test() {
  let js = generator.generate_protocol_wire_js("json", "test_hash_abc123")

  // When a Response frame's value can't be decoded (unknown user type),
  // the error must include the requestId so the transport can clear
  // the pending callback and invoke the RPC error handler.
  // The generated code wraps typedJsonToGleamValue in a Response-specific
  // try/catch and returns { kind: "error", requestId, errors } on failure.
  js
  |> string.contains(
    "return new Ok({ kind: \"error\", requestId: frame.request_id, errors: [[\"decode\", e.message",
  )
  |> should.be_true()

  // Push decode failures can return ResultError (no callback to clear)
  js
  |> string.contains(
    "return new ResultError(e.message || \"JSON decode error\");",
  )
  |> should.be_true()
}

pub fn json_wire_js_decode_not_import_custom_type_test() {
  let js = generator.generate_protocol_wire_js("json", "test_hash_abc123")

  // CustomType must not be imported from gleam.mjs
  js |> string.contains("CustomType") |> should.be_false()
}

pub fn json_wire_push_via_broadcast_is_generic_test() {
  // topics.broadcast must accept generic frame types, not just BitArray
  let topics_src =
    simplifile.read("src/rally/runtime/topics.gleam")
    |> result.unwrap("")

  topics_src
  |> string.contains("pub fn broadcast(_topic: String, _frame: a)")
  |> should.be_true()
}

pub fn json_wire_js_runtime_identity_mismatch_rejected_test() {
  // Build the fixture first so the JS modules exist.
  let #(gen_status, _gen_output) =
    run_gleam(fixture_root, ["run", "-m", "rally", "--", "gen"])
  case gen_status {
    0 -> Nil
    _ -> panic as "Fixture rally gen failed"
  }
  build_client_fixture()

  // Run the JS identity decode test via Node.js.
  case find_executable("node") {
    Some(node) -> {
      let #(status, output) =
        run_executable_capturing_ffi(node, [
          "test/rally/identity_decode_test.mjs",
        ])
      let msg =
        "JS identity decode test failed (exit "
        <> int.to_string(status)
        <> "):\n"
        <> output
      case status {
        0 -> Nil
        _ -> panic as msg
      }
    }
    None -> panic as "node executable not found on PATH"
  }
}

pub fn json_wire_server_push_encoder_in_atoms_test() {
  // The generated atoms.erl must contain a properly-exported
  // json_encode_push_value/2 that dispatches page tags to typed
  // JSON encoders.
  let atoms_path = fixture_root <> "/src/generated@public@rpc_atoms.erl"
  let assert Ok(atoms_content) = simplifile.read(atoms_path)

  // Must export both push functions
  atoms_content
  |> string.contains(
    "-export([ensure/0, encode_push_frame/2, json_encode_push_value/2]).",
  )
  |> should.be_true()

  // Must register push_frame_module (the single facade the FFI calls)
  atoms_content
  |> string.contains("persistent_term:put({libero, push_frame_module},")
  |> should.be_true()

  // Must dispatch by page tag
  atoms_content
  |> string.contains(
    "<<\"Public\">> -> 'generated@public@json_codecs':'json_encode_public_pages_home___to_client'(Msg);",
  )
  |> should.be_true()

  atoms_content
  |> string.contains(
    "<<\"PublicNotifications\">> -> 'generated@public@json_codecs':'json_encode_public_pages_notifications___to_client'(Msg);",
  )
  |> should.be_true()

  // Last case arm must NOT have trailing ';' before end
  atoms_content
  |> string.contains("Page -> error({no_json_push_encoder, Page})\n    end.")
  |> should.be_true()

  // Must have encode_push_frame/2 that wraps json_encode_push_value + framing
  atoms_content
  |> string.contains("encode_push_frame(Page, Msg) ->")
  |> should.be_true()
  atoms_content
  |> string.contains("JsonWireMod:encode_push(Page, JsonValue).")
  |> should.be_true()
}

pub fn json_wire_push_frame_decode_runtime_probe_test() {
  // Build the fixture, then run a JS test that verifies the full
  // push frame round-trip: typed JSON encode -> decode -> concrete instance.
  let #(gen_status, _gen_output) =
    run_gleam(fixture_root, ["run", "-m", "rally", "--", "gen"])
  case gen_status {
    0 -> Nil
    _ -> panic as "Fixture rally gen failed"
  }
  build_client_fixture()

  case find_executable("node") {
    Some(node) -> {
      let #(status, output) =
        run_executable_capturing_ffi(node, [
          "test/js/push_frame_decode_test.mjs",
        ])
      let msg =
        "JS server push encode probe failed (exit "
        <> int.to_string(status)
        <> "):\n"
        <> output
      case status {
        0 -> Nil
        _ -> panic as msg
      }
    }
    None -> panic as "node executable not found on PATH"
  }
}

pub fn json_wire_server_push_encode_erlang_probe_test() {
  // Build the fixture so the Erlang atoms module and rally_runtime_ffi
  // are compiled and available.
  let #(gen_status, _gen_output) =
    run_gleam(fixture_root, ["run", "-m", "rally", "--", "gen"])
  case gen_status {
    0 -> Nil
    _ -> panic as "Fixture rally gen failed"
  }
  let #(build_status, _build_output) = run_gleam(fixture_root, ["build"])
  case build_status {
    0 -> Nil
    _ -> panic as "Fixture gleam build failed"
  }

  case find_executable("sh"), find_executable("erl") {
    Some(sh), Some(erl) -> {
      // Run inside the fixture build directory so all dependency
      // ebin dirs are on the code path via wildcard expansion.
      let command =
        "cd "
        <> fixture_root
        <> " && "
        <> erl
        <> " -noshell"
        <> " -pa build/dev/erlang/*/ebin"
        <> " -s push_encode_probe main -s init stop"

      let #(status, output) = run_executable_capturing_ffi(sh, ["-c", command])

      let msg =
        "Erlang push encode probe failed (exit "
        <> int.to_string(status)
        <> "):\n"
        <> output
      case status {
        0 -> Nil
        _ -> panic as msg
      }
    }
    _, _ -> panic as "sh or erl not found on PATH"
  }
}

pub fn json_wire_push_decode_preserves_cross_module_identity_test() {
  // Build the fixture so the JS modules and type registry exist.
  let #(gen_status, _gen_output) =
    run_gleam(fixture_root, ["run", "-m", "rally", "--", "gen"])
  case gen_status {
    0 -> Nil
    _ -> panic as "Fixture rally gen failed"
  }
  build_client_fixture()

  case find_executable("node") {
    Some(node) -> {
      let #(status, output) =
        run_executable_capturing_ffi(node, [
          "test/js/push_decode_identity_test.mjs",
        ])
      let msg =
        "JS push decode identity test failed (exit "
        <> int.to_string(status)
        <> "):\n"
        <> output
      case status {
        0 -> Nil
        _ -> panic as msg
      }
    }
    None -> panic as "node executable not found on PATH"
  }
}
