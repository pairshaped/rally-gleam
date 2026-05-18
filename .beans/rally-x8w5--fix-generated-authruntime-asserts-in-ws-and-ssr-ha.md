---
# rally-x8w5
title: Fix generated auth/runtime asserts in WS and SSR handlers
status: completed
type: bug
priority: high
tags:
    - codegen
    - auth
created_at: 2026-05-18T11:40:56Z
updated_at: 2026-05-18T16:27:27Z
---

Generated WS and SSR handlers contain `let assert Ok(server_context) = effect_state.get_stored_server_context()` and `let assert Ok(db_conn) = system_db.get_conn()` (and similar) in hot paths. Any failure of those internal lookups crashes the live request instead of returning an error response.

Examples in `src/rally/internal/generator/ws_handler.gleam` around lines 220, 229, 268, 277, 298, 313, 429. Same pattern in `src/rally/internal/generator/ssr_handler.gleam` in the auth resolve and `apply_cookies` branches.

## Scope

- [x] Replace generated `let assert Ok(server_context)` and `let assert Ok(db_conn)` with branched handling that produces a real error response.
- [x] WS path: log + send an error frame instead of crashing the handler.
- [x] SSR path: log + return 500 instead of crashing the connection. _Skipped: ssr_handler.gleam does not actually emit these patterns. Grep across the SSR generator turned up no `let assert` patterns on runtime infrastructure._
- [x] Add a regression test (`no_runtime_asserts_in_generated_handlers_test`) that scans emitted handler source for `let assert Ok(` against the runtime infrastructure lookups so this can't loosen by accident.
- [x] Keep app-level asserts (in user code, in pages) out of scope.
- [x] **page_init failure paths must send a response frame, not just log.** _Added in follow-up after initial review: both no-auth and auth `page_init` originally just logged and called `mist.continue(state)`. That left the client hanging on `request_id` until timeout. Now both branches emit `wire.encode_response(request_id:, value: Error("server_unavailable"))` via `mist.send_binary_frame` before continuing. The regression test was extended with `assert_page_init_missing_context_emits_response`, asserted on the no-auth ETF and auth ETF outputs._

## Out of scope

- `let assert` in non-handler generated code (e.g. codec helpers) — separate audit if needed.
- App-level `let assert` patterns in the realworld example.
- JSON-protocol page_init handling: JSON apps never enter the page_init code path (no_auth JSON only handles RPC; auth JSON only handles reauth + RPC). No fix needed there.

## Summary of Changes

`src/rally/internal/generator/ws_handler.gleam`:
- Replaced every `let assert Ok(server_context) = effect_state.get_stored_server_context()` and `let assert Ok(db_conn) = system_db.get_conn()` in emitted code. Twelve total call sites.
- `server_context` lookup: on `Error(Nil)`, generated handler logs `[rally:ws] missing server_context; <context>` and routes to a typed failure for the surface in question:
  - RPC dispatch (text, binary, and the auth-path `rpc_body`): `wire.error_result(request_id, "server_unavailable")` + `wire.send_rpc_result(conn, result)`.
  - page_init (no-auth and auth, ETF): `wire.encode_response(request_id:, value: Error("server_unavailable"))` + `mist.send_binary_frame(conn, response_frame)`. The client gets a structured failure on the same request_id it was waiting on, so it can surface the error instead of hanging.
  - page_update (no-auth uses `wire.error_result`; auth uses `wire.auth_error_result`): standard RPC-style error result.
  - Reauth (binary and text, auth path): logs and skips reauth, falling through to standard handling.
- `db_conn` lookup (purely observability for `system_db.log_to_server`): on `Error(Nil)`, logs `[rally:ws] system_db unavailable; skipping log_to_server` and continues. Logging failure does not impact request handling.

`test/rally/no_runtime_asserts_in_generated_handlers_test.gleam` (new): five regression tests covering the dispatch matrix: no-auth ETF, no-auth JSON, auth ETF with endpoints, auth JSON with endpoints, auth with no endpoints. Each asserts the emitted source contains neither banned `let assert` substring. The no-auth-ETF and auth-ETF tests additionally call `assert_page_init_missing_context_emits_response`, which slices the source between the `failing page_init for` log and the next `mist.continue` and confirms a `wire.encode_response(..., Error("server_unavailable"))` + `mist.send_binary_frame` pair lives in that window.

### Verification

- All 389 tests pass.
- `gleam format --check` clean on both changed files.
- Both fixture (JSON) and realworld example (ETF) regenerate and rebuild without warnings.
- The pre-existing `gleam format failed` warning during downstream_smoke_test is documented expected behavior (`src/rally/internal/format.gleam:43-46`) when generated code references project-only modules; my changes did not introduce a new instance.

### Scope adjustment found during work

ssr_handler.gleam does not emit `let assert Ok(server_context)` or `let assert Ok(db_conn)` anywhere in its generated output. Original review claim was an agent assumption; confirmed by grep. No SSR changes needed.
