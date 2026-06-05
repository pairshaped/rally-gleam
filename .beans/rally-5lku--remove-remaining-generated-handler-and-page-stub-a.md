---
# rally-5lku
title: Remove remaining generated handler and page stub adapters
status: todo
type: task
priority: normal
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:57:32Z
updated_at: 2026-06-05T22:57:32Z
parent: rally-zmpm
---

## What to build

Remove the thin root adapters that exist only because generated Proute/Rally APIs currently require placeholder shapes. Generated SSR should accept load context directly when a load context is configured, and page placeholder scaffolding should disappear once the generated page contract no longer needs authored stubs.

## Acceptance criteria

[ ] Generated server_ssr accepts load_context directly or otherwise removes the need for one-field app SSR handler wrappers.
[ ] Scoreboard app_ssr no longer defines public_load_handlers/admin_load_handlers just to wrap DB load context.
[ ] Proute/Rally no longer requires app-owned page_stub.gleam for standard pages, or the remaining need is documented as an explicit generator limitation.
[ ] Clean regeneration from empty src/generated still works.
[ ] Scoreboard builds and SSR tests pass.

## Blocked by

None - can start immediately.
