import gleeunit/should
import rally/runtime/codec

pub type TestModel {
  TestModel(name: String, count: Int)
}

pub fn codec_encode_decode_roundtrip_test() {
  let model = TestModel(name: "hello", count: 42)
  let encoded = codec.encode_flags(model)
  encoded |> should.not_equal("")
  let assert Ok(decoded) = codec.decode_flags(encoded)
  decoded |> should.equal(model)
}

pub fn codec_simple_string_roundtrip_test() {
  let value = "hello world"
  let encoded = codec.encode_flags(value)
  let assert Ok(decoded) = codec.decode_flags(encoded)
  decoded |> should.equal(value)
}
