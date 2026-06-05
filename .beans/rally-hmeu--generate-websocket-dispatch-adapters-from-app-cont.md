---
# rally-hmeu
title: Generate websocket dispatch adapters from app context
status: completed
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:52Z
updated_at: 2026-06-05T03:51:43Z
parent: rally-kobq
---

This tracks the broader version of `rally-b9c9`: `app_ws.gleam` still contains standard websocket dispatch ceremony. Some of it is already covered by generated `server_ws`, but the app still wires per-page load wrappers, state-to-db extraction, topic join, binary forwarding, and result error adaptation.

App-owned behavior that should remain authored:

- connection authorization state
- deriving app context such as `db` from websocket state
- domain save/load functions on pages
- after-save broadcast timing and event choice

Framework/generated behavior to move:

- per-page load adapter wiring from generated page metadata
- mapping `List(String)` page load errors to Rally transport errors
- decode/send result ceremony
- forwarding topic messages as binary frames
- standard websocket init/close boilerplate where possible

Acceptance criteria:

- `app_ws.gleam` no longer has one wrapper function per page load just to call `load_wire`.
- App still controls authorization gates and broadcast decisions.
- Generated websocket code composes app context with page-owned functions.
- Clean regenerate and websocket smoke pass.



Completed across the websocket cleanup slices. Rally now generates the request decode/result send ceremony, push-frame encoding, topic forwarding helpers, topic runtime, and direct public page load adapters. Scoreboard app_ws still owns connection authorization, context extraction, admin load/save gates, and after-save broadcast choice.

Validation from the final slice:

• Rally gleam build
• Rally gleam test --target erlang -- --module rally/codegen_load_rpc_snapshot_test
• Scoreboard clean regeneration after deleting src/generated/rally and src/generated/libero
• Scoreboard gleam build --target erlang
• Scoreboard gleam build --target javascript
• Scoreboard gleam test --target erlang
• Scoreboard node test/boundary_guard_test.mjs
• Scoreboard node test/ws_result_smoke.mjs
