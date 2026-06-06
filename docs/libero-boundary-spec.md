# Libero Boundary Spec

Status: intended boundary
Date: 2026-05-09
Last checked: 2026-05-13

## Summary

Rally should be a protocol-oblivious consumer of Libero. Rally decides what
messages exist and when to send them. Libero decides how those typed messages
become protocol data and back.

This boundary is represented by generated `protocol_wire` facades. Rally
backs onto Libero for scanning, dispatch generation, wire transforms, protocol
facades, and typed decoders.

The test is simple: Libero should be able to add JSON as a configured protocol
and Rally should not care which protocol is selected. ETF remains valuable and
should continue to be supported. Rally may need regenerated Libero-owned
modules or updated facade imports. It should not need to rewrite WebSocket
transport logic, response handling, push handling, page init, SSR hydration, or
the message inspector because the configured protocol changed.

Rally's generated browser lifecycle glue defaults to ETF. JSON is useful for
non-Gleam tools that call the same handler contract. Rally should benefit from
Libero's protocol choice without owning the choice.

## Ownership

Rally owns:

- Page and route semantics.
- WebSocket lifecycle.
- HTTP routes.
- Reconnect behavior.
- Request timeout behavior.
- Session and topic membership.
- Push delivery policy.
- Message logging and inspector display.
- When page init, request, and push messages are sent.

Libero should own:

- Request envelope shape.
- Response frame shape.
- Push frame shape.
- Typed encode/decode.
- SSR flag encode/decode for Libero-discovered contract values.
- Protocol validation and protocol errors.
- Security limits at the protocol boundary.

Rally code should not care whether Libero uses ETF, JSON, hashes, field-name
objects, positional arrays, or any future protocol shape.

## Current State

Current protocol boundary:

- `rally.gleam` uses Libero type walking, atom generation, wire module
  generation, typed decoder generation, ETF facade generation, and contract
  generation.
- Generated `protocol_wire.gleam` and `protocol_wire.mjs` choose ETF or JSON.
- `transport_ffi.mjs` imports `encode_request` and `decode_server_frame` from
  `./protocol_wire.mjs`.
- Generated `transport.gleam` exposes framework send, register, and read
  helpers instead of raw frame parsing.
- Generated app code uses generated codec and hydration helpers.
- `rally/runtime/wire.gleam` remains as a small ETF wrapper for direct runtime
  helpers.

## Boundary Shape

Rally's transport should look like this conceptually:

```text
send request:
  frame = generated_libero.encode_request("libero", request_id, msg)
  websocket.send(frame)

on websocket message:
  event = generated_libero.decode_server_frame(bytes)
  case event:
    response -> settle callback
    push -> route to push handler
```

Rally may still keep request callback maps, timeout timers, reconnect state, and
debug logging. It should not know how a response frame is represented.

Page init should follow the same rule:

```text
frame = generated_libero.encode_request(page, 0, params)
```

SSR hydration should use generated Libero helpers rather than raw
`decode_safe_raw` plus `apply_typed_decoder` calls in Rally-generated app code.

## Generated Browser Surface

Generated Rally browser code should expose framework operations:

- `send_request(msg, callback)`
- `send_page_init(page, params)`
- `register_push_handler(page, handler)`
- `read_flags()`
- `read_client_context()`

It should not expose raw protocol helpers such as:

- `decode_safe_raw`
- `apply_typed_decoder`
- raw `decode_value`
- raw `encode_value`
- byte-frame parsing helpers

If an advanced consumer needs raw Libero codec functions, it can import Libero
directly. Rally's generated surface should guide normal app code toward the
typed contract.

## Test Plan

- Existing `gleam test` in Rally.
- JS transport tests for response callbacks and framework error routing.
- Snapshot tests for generated Rally, Libero, and browser app code.
- Scoreboard smoke test for SSR, hydration, browser navigation, and save.
- A guard test that generated Rally browser code does not contain
  `decode_safe_raw`, `apply_typed_decoder`, `0x00`, or `0x01`.
- Libero tests for the new frame facade.

## Acceptance Criteria

- Rally WebSocket code never reads protocol tag bytes.
- Rally WebSocket code never slices request IDs out of raw response frames.
- Rally generated browser code does not expose raw decode helpers.
- Rally app generation does not manually apply typed decoders for flags.
- Rally push handling receives decoded protocol events from Libero.
- The Rally Scoreboard smoke path does not match response bytes by hand.
- Adding JSON as a configured Libero protocol would leave Rally's transport
  lifecycle, response handling, push handling, page init, and hydration logic
  unchanged except for regenerated Libero-owned modules.

## Non-Goals

- Move WebSocket lifecycle into Libero.
- Move Rally topics, sessions, or page routing into Libero.
- Remove Rally's message inspector.
- Remove Libero's low-level codec functions from Libero itself.

The goal is not to make Rally smaller at all costs. The goal is to make Rally's
remaining code about Rally.
