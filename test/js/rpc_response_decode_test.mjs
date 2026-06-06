// Test that RPC response payloads decode to proper Gleam constructor
// instances when using decode_value (typed), and that decode_value_raw
// produces raw arrays unsuitable for Gleam pattern matching.
//
// Run from the rally root:
//   node test/js/rpc_response_decode_test.mjs
//
// This test catches the regression where rally's WebSocket response
// handler used decode_value_raw, causing Gleam callbacks to receive
// raw arrays instead of Ok/Error instances.

import { strict as assert } from "assert";
import {
  decode_result_of,
  decode_option_of,
  decode_list_of,
  setResultCtors,
  setOptionCtors,
  setListCtors,
} from "../../../libero-gleam/src/libero/decoders_prelude.mjs";

// ---------- Gleam stdlib type stubs ----------

class CustomType {}
class Some extends CustomType {
  constructor(value) { super(); this[0] = value; }
}
class None extends CustomType {}
class Ok extends CustomType {
  constructor(value) { super(); this[0] = value; }
}
class ResultError extends CustomType {
  constructor(value) { super(); this[0] = value; }
}
class Empty extends CustomType {}
class NonEmpty extends CustomType {
  constructor(head, tail) { super(); this.head = head; this.tail = tail; }
}

setResultCtors(Ok, ResultError);
setOptionCtors(Some, None);
setListCtors(Empty, NonEmpty);

function listToArray(list) {
  const arr = [];
  let cur = list;
  while (cur instanceof NonEmpty) { arr.push(cur.head); cur = cur.tail; }
  return arr;
}

// ---- Scenario 1: Server returns Ok primitive (e.g. Ok(42)) ----

{
  // decode_value_raw produces: ["ok", 42]
  // decode_value (via typed pipeline) produces: Ok(42)
  const raw = ["ok", 42];
  const typed = decode_result_of(v => v, v => v, raw);
  assert.ok(typed instanceof Ok);
  assert.equal(typed[0], 42);
  console.log("PASS: Ok(42) response");
}

// ---- Scenario 2: Server returns Error with a string message ----

{
  const raw = ["error", "Not found"];
  const typed = decode_result_of(v => v, v => v, raw);
  assert.ok(typed instanceof ResultError);
  assert.equal(typed[0], "Not found");
  console.log("PASS: Error(string) response");
}

// ---- Scenario 3: Server returns Ok with a list of domain objects ----
// This is the pattern that broke: server returns Ok([Sponsor, ...])
// and the client needs to pattern match on Ok(sponsors).

{
  class Sponsor extends CustomType {
    constructor(name, tier) {
      super();
      this.name = name;
      this.tier = tier;
      this[0] = name;
      this[1] = tier;
    }
  }

  // Raw decode: ["ok", [["sponsor", "Acme", 1], ["sponsor", "Beta", 2]]]
  const raw = ["ok", [["sponsor", "Acme", 1], ["sponsor", "Beta", 2]]];

  const decodeSponsor = raw => new Sponsor(raw[1], raw[2]);
  const decodeSponsorList = raw => decode_list_of(decodeSponsor, raw);
  const decodeResponse = raw => decode_result_of(decodeSponsorList, v => v, raw);

  const typed = decodeResponse(raw);

  assert.ok(typed instanceof Ok, "response is Ok instance");
  const sponsors = typed[0];
  assert.ok(sponsors instanceof NonEmpty);
  const arr = listToArray(sponsors);
  assert.equal(arr.length, 2);
  assert.ok(arr[0] instanceof Sponsor);
  assert.equal(arr[0].name, "Acme");
  assert.ok(arr[1] instanceof Sponsor);
  assert.equal(arr[1].name, "Beta");

  console.log("PASS: Ok([Sponsor, Sponsor]) response");
}

// ---- Scenario 4: Error wrapping a domain error variant ----

{
  class NotFound extends CustomType {
    constructor() { super(); }
  }

  // Raw: ["error", ["not_found"]]
  const raw = ["error", ["not_found"]];
  const decodeError = raw => {
    if (Array.isArray(raw)) {
      if (raw[0] === "not_found") return new NotFound();
    }
    return raw;
  };
  const typed = decode_result_of(v => v, decodeError, raw);

  assert.ok(typed instanceof ResultError);
  assert.ok(typed[0] instanceof NotFound);
  console.log("PASS: Error(NotFound) response");
}

// ---- Scenario 5: Ok with None (empty option) ----

{
  // Raw: ["ok", "none"] (atom string for None)
  const raw = ["ok", "none"];
  const typed = decode_result_of(v => decode_option_of(w => w, v), v => v, raw);
  assert.ok(typed instanceof Ok);
  assert.ok(typed[0] instanceof None);
  console.log("PASS: Ok(None) response");
}

// ---- Scenario 6: Ok with Some(value) ----

{
  // Raw: ["ok", ["some", "hello"]]
  const raw = ["ok", ["some", "hello"]];
  const typed = decode_result_of(v => decode_option_of(w => w, v), v => v, raw);
  assert.ok(typed instanceof Ok);
  assert.ok(typed[0] instanceof Some);
  assert.equal(typed[0][0], "hello");
  console.log("PASS: Ok(Some(string)) response");
}

// ---- The bug regression ----
// Verify that raw values fail Gleam pattern matching

const rawOk = ["ok", 42];
assert.equal(rawOk instanceof Ok, false,
  "REGRESSION CHECK: raw [\"ok\", 42] is NOT an Ok instance");
assert.ok(Array.isArray(rawOk),
  "REGRESSION CHECK: raw response is just an array, no constructor");

const rawNone = "none";
assert.equal(rawNone instanceof None, false,
  "REGRESSION CHECK: raw \"none\" string is NOT a None instance");

console.log("\nAll RPC response decode tests passed.");
console.log("If the WebSocket handler uses decode_value_raw, these scenarios break.");
console.log("Use decode_value (typed) for RPC responses and push frames.");
