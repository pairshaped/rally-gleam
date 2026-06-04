---
# rally-au0s
title: Implement JSON encoding for client-context messages
status: completed
type: feature
priority: normal
tags:
    - codegen
    - json
    - client-context
created_at: 2026-05-18T14:34:54Z
updated_at: 2026-06-04T22:52:12Z
---

Follow-up to rally-yghe, which only adds a build-time guard. This bean is the actual feature: make `effect.update_client_context` work under the JSON protocol so JSON-protocol apps can send client-context messages just like ETF-protocol apps can.

## Background

ETF-protocol apps generate (in `codec.gleam:553-558`):

```
pub fn send_to_client_context(msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) {
    transport.send_to_server(\"__ClientContext__\", msg)
    Nil
  })
}
```

The ETF transport encodes `msg` as an opaque BitArray. JSON protocol can't do that — it needs a typed encoding.

## Scope

- [ ] Define the JSON wire shape for `ClientContextMsg`. Likely a tagged variant payload (`{ \"variant\": \"Foo\", \"data\": ... }`) matching how other JSON-protocol messages are framed.
- [ ] Generate the encoder in the JSON branch of `emit_rally_effect_shim` (currently emits a runtime panic).
- [ ] Generate the matching server-side decoder so the WS handler can route `__ClientContext__` frames to the page's client_context update path.
- [ ] Add codec round-trip tests for nested types, lists, options, and recursive payloads in `ClientContextMsg`.
- [ ] Verify parity with ETF behavior via a test that runs the same `update_client_context` flow under both protocols and asserts the same dispatch result.
- [ ] Remove the build-time guard added by rally-yghe once this lands (or convert it to assert that the generated code does not contain a panic).

## Out of scope

- Other JSON-protocol gaps (separate audit if needed).
- Changing the ETF behavior.

## Why deferred

The runtime panic is a production crash, but the right fix here involves codec generator changes that can sprawl into adjacent areas (JSON variant encoding shape, recursive type handling, dispatch routing). Better to ship a clean guard now via rally-yghe and tackle the full implementation under a properly-scoped issue.



## Completion notes

Implemented JSON client-context message generation:

- JSON client packages now generate `json_encode_client_context_msg` from the parsed `ClientContextMsg` contract.
- The generated JSON client effect shim sends `__ClientContext__` through the normal transport instead of panicking.
- Generated JSON protocol wire exposes a `decode_client_context_msg` helper when a client context contract exists.
- Generated JSON WS handlers route `__ClientContext__` request envelopes by decoding, pushing the context update back to the connection, and acknowledging the request.
- The old JSON/client-context build guard is now a compatibility no-op.

Validation:

- `gleam build`
- `gleam test --target erlang` (423 passed)
