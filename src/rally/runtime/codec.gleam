//// SSR flag serialization. Encodes a page's Model as base64 ETF for
//// embedding in HTML (server-side), and decodes it back during client
//// hydration. Delegates the actual ETF encode/decode to libero via wire.

import gleam/bit_array
import gleam/result
import rally/runtime/wire

/// Encode any Gleam value to a base64 ETF string for embedding in HTML.
/// Used server-side during SSR to serialize the page model into flags.
pub fn encode_flags(value: a) -> String {
  value
  |> wire.encode
  |> bit_array.base64_encode(True)
}

/// Decode a base64 ETF string back to a Gleam value.
/// Used client-side during hydration to read the server-rendered model.
pub fn decode_flags(flags: String) -> Result(a, Nil) {
  use bits <- result.try(case bit_array.base64_decode(flags) {
    Ok(bits) -> Ok(bits)
    _ -> Error(Nil)
  })
  case wire.decode_safe(bits) {
    Ok(value) -> Ok(value)
    _ -> Error(Nil)
  }
}
