---
# rally-ic6f
title: Make Rally build target Rally Scoreboard unified source
status: completed
type: epic
priority: high
tags:
    - rally
    - build
created_at: 2026-06-06T04:32:08Z
updated_at: 2026-06-06T05:45:13Z
---

Rally build should target the Rally Scoreboard unified-source architecture. The legacy `.generated_clients` pipeline and `server_*` authoring model should stop being the normal path.

Child beans:
- rally-51ow: make `rally build` run unified source generation.
- rally-unag: generate Rally Scoreboard style scaffold.
- rally-dn07: update examples and smoke tests for unified build.
- rally-09rm: move generated-client pipeline behind an explicit legacy boundary.
- rally-tn73: rename load-rpc internals/user-facing vocabulary.
- rally-536z: delete legacy generated-client pipeline once callers are gone.

Current migration stance: keep old generator code alive only behind explicit legacy commands until scaffold/tests/docs have moved. Do not present `.generated_clients`, `server_*`, `server_init`, or `server_update` as the Rally default.

## Summary of Changes

`rally build` now targets the Rally Scoreboard unified-source path: Marmot when configured, Proute when present, Rally/Libero generation into `src/generated/**`, and Erlang/JavaScript builds. The scaffold, docs, examples, smoke tests, CLI/config surface, and legacy generated-client code have been moved to the unified architecture.

Validation: `bin/check-auth-codegen` passes; stale-term `rg` scan is clean; `gleam format && gleam test` passes with 189 tests.
