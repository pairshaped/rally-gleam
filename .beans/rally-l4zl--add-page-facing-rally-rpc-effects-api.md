---
# rally-l4zl
title: Add page-facing Rally RPC effects API
status: completed
type: task
priority: high
tags:
    - codegen
    - api
created_at: 2026-06-04T23:18:28Z
updated_at: 2026-06-04T23:31:35Z
parent: rally-oymv
---

Page modules should not import generated transport/result internals directly. Add a stable page-facing Rally RPC effects API and regenerate page call sites to use it.

Problem:
- Scoreboard pages call `generated/rally/client_transport.send_*` directly.
- Page modules also map `generated/rally/result.ApiLoadError` and `ApiSaveError` directly.
- This makes generated internals part of the user authoring surface and conflicts with the ADR 0008 direction of page-local RPC effects.

Scope:
- Design the page-facing API shape, likely in the spirit of `server.send(ServerMsg, on_result:)` or generated page-local wrappers with a stable Rally namespace.
- Hide generated transport and result module details from authored page modules.
- Keep page-owned domain result mapping and user-facing error messages in the page.
- Keep generated code free to consume Libero and transport internals behind the API.

Non-goals:
- Do not remove page-local `wire.gleam` contracts.
- Do not generate page domain behavior or page update logic.
- Do not make Libero disappear as a runtime dependency of generated code.

Acceptance:
- Scoreboard page modules no longer import `generated/rally/client_transport` or `generated/rally/result` directly.
- Page code can request load/save/update effects through a stable Rally-facing API.
- Existing page behavior is unchanged.
- Tests or guard assertions cover the public API shape and prevent direct generated transport imports in authored page code.


## Completion notes

Generated a page-facing `src/generated/rally/server.gleam` wrapper for load RPC effects:

- The wrapper exposes `load_*` and `save_*` functions for page modules.
- Authored pages no longer need to import `generated/rally/client_transport` or `generated/rally/result` directly.
- The wrapper maps transport-level `ApiLoadError` and `ApiSaveError` into page-facing `server.LoadError` and `server.SaveError` values.
- Generated transport/protocol/result modules remain internal generated plumbing and may still consume Libero/Rally internals.
- Added snapshot coverage for the generated page-facing server module.
- Regenerated Scoreboard load RPC output and migrated all authored page modules to `generated/rally/server`.

Validation:

- Rally `gleam build`
- Rally `gleam test --target erlang -- --module rally/codegen_load_rpc_snapshot_test` (426 passed)
- Scoreboard `gleam build --target javascript`
- Scoreboard `gleam build --target erlang`
- Scoreboard authored pages search for `generated/rally/client_transport`, `generated/rally/result`, `api_client`, `wire_result`, and `ApiLoadError`/`ApiSaveError` returned no matches.
