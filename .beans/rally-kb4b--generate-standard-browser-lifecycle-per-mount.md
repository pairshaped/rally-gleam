---
# rally-kb4b
title: Generate standard browser lifecycle per mount
status: completed
type: task
priority: normal
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:57:15Z
updated_at: 2026-06-05T23:22:58Z
parent: rally-zmpm
---

## What to build

Move the repeated public/admin browser lifecycle ceremony into Rally generated glue while keeping app shell and shared-state construction explicit. The generated lifecycle should own current path boot, initial page load, page update/effect mapping, server-frame handling, navigation effects, browser navigation listeners, dark-mode runtime effects, and topic sync.

## Acceptance criteria

[x] Rally generated browser glue owns the repeated Model/Msg/update/navigation lifecycle for standard mounts.
[x] Scoreboard still provides app shell rendering and shared-state construction for public/admin mounts.
[x] Public and admin app entrypoints shrink to app decisions and mount config rather than duplicated lifecycle code.
[x] Topic sync still follows loaded page state.
[x] Dark-mode toggle behavior still works without app-owned storage/application mechanics.
[x] Browser smoke passes for public navigation, admin navigation, dark mode, and broadcasts.

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
