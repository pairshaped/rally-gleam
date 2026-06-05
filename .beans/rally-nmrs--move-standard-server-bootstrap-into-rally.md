---
# rally-nmrs
title: Move standard server bootstrap into Rally
status: completed
type: task
priority: high
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:56:58Z
updated_at: 2026-06-05T23:09:48Z
parent: rally-zmpm
---

## What to build

Make the standard Rally template server bootstrap own process configuration and boring HTTP setup for Scoreboard. The app should not hand-write PORT parsing, DB path constants, DB opening, auth session setup, static asset routing, or default public/admin/websocket dispatch shell.

The app still owns DB schema and page SQL/data behavior. Rally opens the configured DB and passes it as load context to generated/server runtime surfaces.

## Acceptance criteria

[x] Rally reads app/package identity from gleam.toml or generated metadata for standard bootstrap.
[x] Rally owns PORT env override parsing and fallback behavior.
[x] Rally owns DB path config from gleam.toml with env override and opens the DB for the standard template app.
[x] Rally owns auth session config lookup and error reporting for standard bootstrap.
[x] Rally owns default /assets serving from priv/static.
[x] Scoreboard no longer needs app_config.gleam for PORT handling.
[x] Scoreboard server root no longer hand-writes static routing or DB opening for the standard case.
[x] Scoreboard builds, boundary guard, websocket smoke, and browser smoke pass.

## Blocked by

None - can start immediately.


## Validation

- rally-gleam: `gleam test`
- rally-scoreboard-example: `gleam build --target erlang`
- rally-scoreboard-example: `gleam build --target javascript`
- rally-scoreboard-example: `node test/boundary_guard_test.mjs`
- rally-scoreboard-example: `TEMP=./tmp gleam test --target erlang`
- rally-scoreboard-example: `node test/ws_result_smoke.mjs`
- rally-scoreboard-example: `npm run test:browser`
