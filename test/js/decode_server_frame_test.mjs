// Behavioral test: prove that decode_server_frame returns properly
// structured response and push frames with correctly typed values.
//
// PREREQUISITE — libero's ETF wire FFI imports from gleam_stdlib, which
// only exists after `gleam build -t javascript`. This test imports
// libero source directly, so it needs shim files at the expected paths.
//
// Run via the wrapper script (handles shim setup/teardown):
//   test/js/run_decode_server_frame_test.sh
//
// Or run directly after creating shims manually:
//   mkdir -p ../../libero/gleam_stdlib/gleam
//   ... (create gleam.mjs, option.mjs, dict.mjs, error.mjs shims)
//   node test/js/decode_server_frame_test.mjs
//
// Infrastructure note: this test is blocked on a proper JS test harness
// for the libero+rally monorepo. The shim approach works but is fragile.
// See P3 in the contract-boundary review.

import { strict as assert } from "assert";
import {
  decode_server_frame,
  encode_value,
} from "../../../libero-gleam/src/libero/etf/wire_ffi.mjs";

// ---------- Helpers ----------

function isOk(value) {
  return value && value.constructor && value.constructor.name === "Ok";
}

function isError(value) {
  return value && value.constructor && value.constructor.name === "Error";
}

function responseFrame(requestId, value) {
  const payload = encode_value(value).rawBuffer;
  const bytes = new Uint8Array(5 + payload.byteLength);
  bytes[0] = 0;
  new DataView(bytes.buffer).setUint32(1, requestId);
  bytes.set(payload, 5);
  return bytes.buffer;
}

function pushFrame(module, value) {
  const payload = encode_value([module, value]).rawBuffer;
  const bytes = new Uint8Array(1 + payload.byteLength);
  bytes[0] = 1;
  bytes.set(payload, 1);
  return bytes.buffer;
}

// ---------- Response frame with integer ----------

{
  const payload = encode_value(123);
  const bytes = new Uint8Array(5 + payload.rawBuffer.byteLength);
  bytes[0] = 0;
  new DataView(bytes.buffer).setUint32(1, 42);
  bytes.set(payload.rawBuffer, 5);

  const result = decode_server_frame(bytes.buffer);
  assert.ok(isOk(result), "decode_server_frame returns Ok wrapper");
  const frame = result[0];
  assert.equal(frame.kind, "response");
  assert.equal(frame.requestId, 42);
  assert.equal(frame.value, 123);
  console.log("PASS: response frame with integer value");
}

// ---------- Response frame with string ----------

{
  const payload = encode_value("hello");
  const bytes = new Uint8Array(5 + payload.rawBuffer.byteLength);
  bytes[0] = 0;
  new DataView(bytes.buffer).setUint32(1, 7);
  bytes.set(payload.rawBuffer, 5);

  const result = decode_server_frame(bytes.buffer);
  assert.ok(isOk(result));
  const frame = result[0];
  assert.equal(frame.kind, "response");
  assert.equal(frame.requestId, 7);
  assert.equal(frame.value, "hello");
  console.log("PASS: response frame with string value");
}

// ---------- Response frame with tuple ----------

{
  const payload = encode_value([1, 2, 3]);
  const bytes = new Uint8Array(5 + payload.rawBuffer.byteLength);
  bytes[0] = 0;
  new DataView(bytes.buffer).setUint32(1, 99);
  bytes.set(payload.rawBuffer, 5);

  const result = decode_server_frame(bytes.buffer);
  assert.ok(isOk(result));
  const frame = result[0];
  assert.equal(frame.kind, "response");
  assert.equal(frame.requestId, 99);
  assert.ok(Array.isArray(frame.value));
  assert.deepEqual(frame.value, [1, 2, 3]);
  console.log("PASS: response frame with tuple value");
}

// ---------- Push frame with integer value ----------

{
  const raw = pushFrame("pages/home", 99);
  const result = decode_server_frame(raw);
  assert.ok(isOk(result));

  const frame = result[0];
  assert.equal(frame.kind, "push");
  assert.equal(frame.module, "pages/home");
  assert.equal(frame.value, 99);
  console.log("PASS: push frame with integer value");
}

// ---------- Push frame with string value ----------

{
  const raw = pushFrame("core/topic", "pushed value");
  const result = decode_server_frame(raw);
  assert.ok(isOk(result));

  const frame = result[0];
  assert.equal(frame.kind, "push");
  assert.equal(frame.module, "core/topic");
  assert.equal(frame.value, "pushed value");
  console.log("PASS: push frame with string value");
}

// ---------- Error cases ----------

{
  const result = decode_server_frame(new Uint8Array([]).buffer);
  assert.ok(isError(result));
  console.log("PASS: empty frame returns Error");
}

{
  const result = decode_server_frame(new Uint8Array([9, 0, 0, 0, 1]).buffer);
  assert.ok(isError(result));
  console.log("PASS: unknown tag byte returns Error");
}

// ---------- Verify frame.kind routing covers both paths ----------

{
  const r = responseFrame(1, "resp");
  const result = decode_server_frame(r);
  assert.ok(isOk(result));
  assert.equal(result[0].kind, "response");
  assert.equal(typeof result[0].requestId, "number");
  console.log("PASS: response frame has kind=\"response\" and numeric requestId");
}

{
  const r = pushFrame("m", "val");
  const result = decode_server_frame(r);
  assert.ok(isOk(result));
  assert.equal(result[0].kind, "push");
  assert.equal(typeof result[0].module, "string");
  console.log("PASS: push frame has kind=\"push\" and string module");
}

console.log("\nAll decode_server_frame behavioral tests passed.");
