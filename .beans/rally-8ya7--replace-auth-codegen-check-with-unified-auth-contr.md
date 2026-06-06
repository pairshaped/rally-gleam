---
# rally-8ya7
title: Replace auth codegen check with unified auth contract
status: completed
type: task
priority: normal
created_at: 2026-06-06T05:24:01Z
updated_at: 2026-06-06T05:44:51Z
parent: rally-536z
---

The bin/check-auth-codegen script still builds a generated-client style fixture with [[tools.rally.clients]], src/server_context.gleam, src/public/shell.html, and server_* handlers. Replace it with a unified Rally Scoreboard style auth/codegen smoke check or remove it if equivalent unified coverage already exists.

Acceptance:
- bin/check-auth-codegen no longer references generated-client config, server_context scaffold files, shell.html, or server_* RPC handlers.
- The replacement still verifies auth-related generated code, or an existing test is extended to cover the same contract.
- Relevant test command passes.

## Summary of Changes

Replaced the old generated-client auth compile fixture with a unified Rally Scoreboard style smoke app. The script now uses Proute mounts, page shared state, `[tools.rally.context]`, page-local load/save contracts, and verifies the generated admin WebSocket auth gate before compiling the Erlang target. It no longer creates `server_context.gleam`, shell files, `[[tools.rally.clients]]`, or `server_*` handlers.

Validation: `bin/check-auth-codegen` passes; stale-term `rg` scan is clean; `gleam format && gleam test` passes with 189 tests.
