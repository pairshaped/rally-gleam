---
# rally-p7k2
title: Discover or configure load-RPC push payload contracts
status: completed
type: task
priority: high
tags:
    - boundary-cleanup
    - codegen
created_at: 2026-06-05T04:12:00Z
updated_at: 2026-06-05T04:35:00Z
parent: rally-kobq
---

Rally load-RPC generation currently hardcodes the websocket push payload type as `broadcasts.Event`. That matches the scoreboard example, but it is app-specific knowledge inside Rally.

Goal:

- Rally should discover or accept explicit configuration for push payload contracts.
- Generated client/server protocol modules should import and encode the declared push payload type(s), not assume `broadcasts.Event`.
- Scoreboard can continue to use `broadcasts.Event`, but that choice should live in app-owned code or app configuration.

Acceptance criteria:

- `src/rally/internal/generator/load_rpc.gleam` no longer hardcodes `import broadcasts` or `broadcasts.Event`.
- The scoreboard example still receives and applies `BroadcastGameUpdated` push frames.
- Libero still owns codec generation for the push payload type.
- Clean regeneration and Scoreboard websocket smoke pass.

Completion notes:

- Added explicit load-RPC push payload configuration at `[tools.rally.load_rpc.push]` with `module` and `type` fields.
- `load_rpc.generate` and `load_rpc.libero_type_seeds` now take `Option(PushContract)`.
- Generated client/server protocol and websocket modules no longer hardcode `broadcasts.Event`; configured apps import the declared module as `push_payload`.
- Apps without a push contract generate no push-frame API and do not seed Libero with a fake broadcast type.
- Scoreboard declares `broadcasts.Event` as its app-owned push payload contract.

Validation:

- Rally: `gleam build`
- Rally: `gleam test --target erlang -- --module rally/codegen_load_rpc_snapshot_test`
- Scoreboard: `gleam run -m rally load-rpc`
- Scoreboard: `gleam build --target erlang`
- Scoreboard: `gleam build --target javascript`
- Scoreboard: `node test/boundary_guard_test.mjs`
- Scoreboard: `node test/ws_result_smoke.mjs`
