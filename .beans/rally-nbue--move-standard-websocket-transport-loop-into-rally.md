---
# rally-nbue
title: Move standard websocket transport loop into Rally
status: completed
type: task
priority: normal
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:57:23Z
updated_at: 2026-06-05T23:30:06Z
parent: rally-zmpm
---

## What to build

Move the standard Mist websocket transport loop into Rally runtime or generated glue. Scoreboard should not own topic selector setup, topic leave/sync mechanics, custom-frame forwarding, binary client-frame dispatch ceremony, or stop/continue handling for the standard app.

The app still owns broadcast topics, broadcast events/data, auth policy, and page load/save behavior.

## Acceptance criteria

[x] Rally owns websocket init/handler/close ceremony for the standard template app.
[x] Rally owns topic selector setup, join/leave sync, and cleanup on close.
[x] Rally owns custom-frame forwarding and binary client-frame dispatch ceremony.
[x] Scoreboard provides only app-specific callbacks or config: load context, auth context, and broadcast domain definitions.
[x] Broadcast-except-origin behavior is preserved.
[x] websocket smoke, boundary guard, and browser smoke pass.

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
