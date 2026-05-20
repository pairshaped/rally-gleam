#!/usr/bin/env sh
set -eu
# Wrapper for auth_error_handling_test.mjs.
#
# Creates a self-contained temp directory under tmp/ (already gitignored
# and used by other test tooling) with minimal gleam_stdlib and libero
# shims, plus a copy of transport_ffi.mjs and its generated protocol facade
# positioned so relative imports resolve inside the temp tree. No files outside
# tmp/ are created or deleted.
#
# Run: test/js/run_auth_error_test.sh

RALLY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TEST_DIR="$RALLY_ROOT/tmp/auth_error_test"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Lay out the tree so transport_ffi.mjs's relative imports resolve:
#   ../../gleam_stdlib/gleam.mjs  ->  tmp/auth_error_test/gleam_stdlib/gleam.mjs
#   ../../libero/libero/error.mjs   -> tmp/auth_error_test/libero/libero/error.mjs
#   ./protocol_wire.mjs             -> tmp/auth_error_test/src/generated/protocol_wire.mjs
mkdir -p "$TEST_DIR/src/generated"
mkdir -p "$TEST_DIR/gleam_stdlib/gleam"
mkdir -p "$TEST_DIR/libero/libero"

cp "$RALLY_ROOT/src/rally/runtime/transport_ffi.mjs" "$TEST_DIR/src/generated/"

# --- gleam_stdlib stubs ---

cat > "$TEST_DIR/gleam_stdlib/gleam.mjs" << 'MODEOF'
export class CustomType {}
export class Ok extends CustomType {
  constructor(value) { super(); this[0] = value; }
}
export class Error extends CustomType {
  constructor(value) { super(); this[0] = value; }
}
export class BitArray extends CustomType {
  constructor(rawBuffer) { super(); this.rawBuffer = rawBuffer; }
}
export class Empty extends CustomType {}
export class NonEmpty extends CustomType {
  constructor(head, tail) { super(); this.head = head; this.tail = tail; }
}
MODEOF

# --- libero stubs ---

cat > "$TEST_DIR/libero/libero/rpc_ffi.mjs" << 'MODEOF'
import { Ok, Error as ResultError } from "../../gleam_stdlib/gleam.mjs";
export function encode_request(_module, _requestId, _msg) {
  return new Uint8Array([0]).buffer;
}
export function decode_server_frame(_data) {
  return new ResultError("stub: not implemented");
}
MODEOF

cat > "$TEST_DIR/libero/libero/error.mjs" << 'MODEOF'
import { CustomType } from "../../gleam_stdlib/gleam.mjs";
export class MalformedRequest extends CustomType {}
export class UnknownFunction extends CustomType {
  constructor(name) { super(); this.name = name; }
}
export class InternalError extends CustomType {
  constructor(trace_id, message) { super(); this.trace_id = trace_id; this.message = message; }
}
MODEOF

# --- generated protocol facade shim ---

cat > "$TEST_DIR/src/generated/protocol_wire.mjs" << 'MODEOF'
export { encode_request, decode_server_frame } from "../../libero/libero/rpc_ffi.mjs";
MODEOF

node "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/auth_error_handling_test.mjs"
