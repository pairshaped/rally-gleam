---
# rally-5lku
title: Remove remaining generated handler and page stub adapters
status: completed
type: task
priority: normal
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:57:32Z
updated_at: 2026-06-05T23:36:34Z
parent: rally-zmpm
---

## What to build

Remove the thin root adapters that exist only because generated Proute/Rally APIs currently require placeholder shapes. Generated SSR should accept load context directly when a load context is configured, and page placeholder scaffolding should disappear once the generated page contract no longer needs authored stubs.

## Acceptance criteria

[x] Generated server_ssr accepts load_context directly or otherwise removes the need for one-field app SSR handler wrappers.
[x] Scoreboard app_ssr no longer defines public_load_handlers/admin_load_handlers just to wrap DB load context.
[x] Proute/Rally no longer requires app-owned page_stub.gleam for standard pages, or the remaining need is documented as an explicit generator limitation.
[x] Clean regeneration from empty src/generated still works.
[x] Scoreboard builds and SSR tests pass.

## Blocked by

None - can start immediately.


## Validation

- rally-gleam: `gleam test`
- rally-scoreboard-example: clean regeneration from empty `src/generated` with `gleam run -m marmot`, `gleam run -m proute`, and `gleam run -m rally load-rpc`
- rally-scoreboard-example: `gleam build --target erlang`
- rally-scoreboard-example: `gleam build --target javascript`
- rally-scoreboard-example: `node test/boundary_guard_test.mjs`
- rally-scoreboard-example: `TEMP=./tmp gleam test --target erlang`
- rally-scoreboard-example: `node test/ws_result_smoke.mjs`
- rally-scoreboard-example: `npm run test:browser`
