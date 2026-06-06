//// Guard: Rally transport surfaces must not contain byte-level frame
//// awareness or raw codec imports. Libero owns the frame boundary,
//// request envelope, and typed decode pipeline.
////
//// If this test fails, someone reintroduced a leak that Step 2/3/4
//// closed: tag-byte inspection, manual frame header slicing, raw
//// decode imports, or low-level encode names.

import gleam/string
import simplifile

pub fn transport_ffi_has_no_byte_level_frame_awareness_test() {
  let assert Ok(content) =
    simplifile.read("src/rally/runtime/transport_ffi.mjs")

  // Must NOT inspect frame tag bytes
  let assert False = string.contains(content, "0x00")
  let assert False = string.contains(content, "0x01")

  // Must NOT use low-level encode/decode names
  let assert False = string.contains(content, "encode_call")
  let assert False = string.contains(content, "decode_value(")
  let assert False = string.contains(content, "decode_safe_raw")
  let assert False = string.contains(content, "decodeTyped")
  let assert False = string.contains(content, "tag_response")
  let assert False = string.contains(content, "tag_push")

  // Must NOT slice frame headers manually
  let assert False = string.contains(content, "DataView")
  let assert False = string.contains(content, "getUint32")

  // Must USE the boundary API
  let assert True = string.contains(content, "decode_server_frame")
  let assert True = string.contains(content, "encode_request")

  // Must NOT import libero wire FFI directly
  let old_rpc_module = "rpc" <> "_ffi.mjs"
  let assert False = string.contains(content, old_rpc_module)
  let assert False = string.contains(content, "libero/etf/wire_ffi.mjs")
  let assert False = string.contains(content, "libero/json/wire_ffi.mjs")

  // Must import from the protocol_wire facade
  let assert True = string.contains(content, "./protocol_wire.mjs")
}

pub fn transport_ffi_sends_gleam_bit_array_as_browser_binary_test() {
  let assert Ok(content) =
    simplifile.read("src/rally/runtime/transport_ffi.mjs")

  let assert True =
    string.contains(content, "function toWebSocketPayload(payload)")
  let assert True =
    string.contains(
      content,
      "const payload = toWebSocketPayload(encode_request(module, requestId, msg));",
    )
  let assert True =
    string.contains(
      content,
      "const payload = toWebSocketPayload(encode_request(module, 0, params));",
    )
  let assert True = string.contains(content, "return payload.rawBuffer;")
}
