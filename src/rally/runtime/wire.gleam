//// Thin wrapper over libero's ETF wire protocol. Delegates all encode,
//// decode, request/response framing, and push framing to libero/wire.
//// This is the legacy direct import path; new generated code uses the
//// protocol_wire facade instead.

import gleam/dynamic.{type Dynamic}
import libero/error.{type DecodeError}
import libero/wire as libero_wire

/// Raw ETF encode. Not safe for user custom types (bare atoms, not
/// hashed). Only correct for pre-encoded values or primitives.
pub fn encode(value: a) -> BitArray {
  libero_wire.encode(value)
}

pub fn decode(data: BitArray) -> a {
  libero_wire.decode(data)
}

pub fn decode_safe(data: BitArray) -> Result(a, DecodeError) {
  libero_wire.decode_safe(data)
}

pub fn decode_request(
  data: BitArray,
) -> Result(#(String, Int, Dynamic), DecodeError) {
  libero_wire.decode_request(data)
}

pub fn encode_request(
  module module: String,
  request_id request_id: Int,
  msg msg: a,
) -> BitArray {
  libero_wire.encode_request(module:, request_id:, msg:)
}

pub fn encode_response(request_id request_id: Int, value value: a) -> BitArray {
  libero_wire.encode_response(request_id:, value:)
}

pub fn tag_response(
  request_id request_id: Int,
  data data: BitArray,
) -> BitArray {
  libero_wire.tag_response(request_id:, data:)
}

pub fn encode_push(module module: String, value value: a) -> BitArray {
  libero_wire.encode_push(module:, value:)
}

pub fn tag_push(module module: String, msg msg: a) -> BitArray {
  encode_push(module:, value: msg)
}

pub fn variant_tag(value: Dynamic) -> Result(String, Nil) {
  libero_wire.variant_tag(value)
}

pub fn coerce(value: a) -> b {
  do_coerce(value)
}

@external(erlang, "rally_runtime_wire_ffi", "tuple_element")
pub fn tuple_element(_tuple: Dynamic, _index: Int) -> Dynamic {
  dynamic.nil()
}

@external(erlang, "gleam_stdlib", "identity")
fn do_coerce(value: a) -> b
