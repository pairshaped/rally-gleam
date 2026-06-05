---
# rally-nmrs
title: Move standard server bootstrap into Rally
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:56:58Z
updated_at: 2026-06-05T22:56:58Z
parent: rally-zmpm
---

## What to build

Make the standard Rally template server bootstrap own process configuration and boring HTTP setup for Scoreboard. The app should not hand-write PORT parsing, DB path constants, DB opening, auth session setup, static asset routing, or default public/admin/websocket dispatch shell.

The app still owns DB schema and page SQL/data behavior. Rally opens the configured DB and passes it as load context to generated/server runtime surfaces.

## Acceptance criteria

[ ] Rally reads app/package identity from gleam.toml or generated metadata for standard bootstrap.
[ ] Rally owns PORT env override parsing and fallback behavior.
[ ] Rally owns DB path config from gleam.toml with env override and opens the DB for the standard template app.
[ ] Rally owns auth session config lookup and error reporting for standard bootstrap.
[ ] Rally owns default /assets serving from priv/static.
[ ] Scoreboard no longer needs app_config.gleam for PORT handling.
[ ] Scoreboard server root no longer hand-writes static routing or DB opening for the standard case.
[ ] Scoreboard builds, boundary guard, websocket smoke, and browser smoke pass.

## Blocked by

None - can start immediately.
