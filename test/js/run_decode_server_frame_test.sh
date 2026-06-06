#!/usr/bin/env sh
set -eu
# Wrapper for decode_server_frame_test.mjs.
# Creates the gleam_stdlib shim files that libero's ETF wire FFI
# expects, runs the test, then cleans up.
#
# The shims are needed because libero's JS source imports from
# gleam_stdlib, which only exists after `gleam build -t javascript`.
# Rather than requiring a full JS build, we create minimal stubs.

LIBERO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)/libero-gleam
SHIM_DIR="$LIBERO_ROOT/gleam_stdlib/gleam"
DICT_SHIM="$LIBERO_ROOT/gleam_stdlib/dict.mjs"
ERROR_SHIM="$LIBERO_ROOT/src/libero/error.mjs"

cleanup() {
  rm -rf "$LIBERO_ROOT/gleam_stdlib"
  rm -f "$ERROR_SHIM"
}
trap cleanup EXIT

mkdir -p "$SHIM_DIR"

cat > "$LIBERO_ROOT/gleam_stdlib/gleam.mjs" << 'MODEOF'
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

cat > "$SHIM_DIR/option.mjs" << 'MODEOF'
import { CustomType } from "../gleam.mjs";
export class Some extends CustomType {
  constructor(value) { super(); this[0] = value; }
}
export class None extends CustomType {}
MODEOF

cat > "$SHIM_DIR/dict.mjs" << 'MODEOF'
export function from_list(entries) { return new Map(entries); }
export function to_list(map) { return [...map.entries()]; }
MODEOF

cat > "$DICT_SHIM" << 'MODEOF'
export default class GleamDict {}
MODEOF

cat > "$ERROR_SHIM" << 'MODEOF'
import { CustomType } from "../../gleam_stdlib/gleam.mjs";
export class DecodeError extends CustomType {
  constructor(message) { super(); this.message = message; }
}
MODEOF

node "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/decode_server_frame_test.mjs"
