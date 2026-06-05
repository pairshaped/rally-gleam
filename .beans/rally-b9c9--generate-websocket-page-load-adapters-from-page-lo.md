---
# rally-b9c9
title: Generate websocket page load adapters from page load_wire
status: completed
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:17:11Z
updated_at: 2026-06-05T03:50:44Z
parent: rally-kobq
---

`app_ws.gleam` still contains per-page load adapter functions such as `load_public_standings(state)` that only call `public_standings_page.load_wire(state.db)` and map `List(String)` into `server_ws.LoadError`.

This is user-code ceremony. It exists because generated `server_ws` currently asks the application for a `Handlers(State)` record with one function per discovered load. After page modules grew `load_wire`, many of those functions no longer encode app behavior. They only adapt app websocket state to page load context.

Goal:

- Rally-generated websocket dispatch should call page-owned `load_wire` functions directly where possible.
- App-owned websocket code should provide connection state, context extraction such as `state.db`, authorization gates, and app-owned after-save broadcast behavior.
- Page modules should keep owning domain load/handle behavior and wire result conversion.
- `app_ws.gleam` should not contain one wrapper per page load just to pass `state.db` and map framework error shapes.

Non-goals:

- Do not move app authorization policy into Rally.
- Do not make page modules depend on `app_ws.State` or websocket transport details.
- Do not generate app-owned broadcast decisions.

Acceptance criteria:

- Public load handlers in `app_ws.gleam` no longer need per-page wrapper functions such as `load_public_standings`.
- Admin load/save authorization remains app-owned, either through a small context gate or explicit app callback.
- Generated `server_ws` continues to send correlated results and app-owned after-save broadcast callbacks remain separate.
- Scoreboard builds and websocket smoke tests pass.



Completed by generating public websocket page loads directly from page-owned load_wire functions when [tools.rally.load_rpc.context] names the concrete load context type. Generated server_ws now imports client-loadable page modules, calls load_wire with handlers.load_context(state), and keeps admin/auth-gated loads as app callbacks.

Validated with:

• Rally gleam build
• Rally gleam test --target erlang -- --module rally/codegen_load_rpc_snapshot_test
• Scoreboard clean regeneration after deleting src/generated/rally and src/generated/libero
• Scoreboard gleam build --target erlang
• Scoreboard gleam build --target javascript
• Scoreboard gleam test --target erlang
• Scoreboard node test/boundary_guard_test.mjs
• Scoreboard node test/ws_result_smoke.mjs
