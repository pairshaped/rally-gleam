---
# rally-kb4b
title: Generate standard browser lifecycle per mount
status: todo
type: task
priority: normal
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:57:15Z
updated_at: 2026-06-05T22:57:15Z
parent: rally-zmpm
---

## What to build

Move the repeated public/admin browser lifecycle ceremony into Rally generated glue while keeping app shell and shared-state construction explicit. The generated lifecycle should own current path boot, initial page load, page update/effect mapping, server-frame handling, navigation effects, browser navigation listeners, dark-mode runtime effects, and topic sync.

## Acceptance criteria

[ ] Rally generated browser glue owns the repeated Model/Msg/update/navigation lifecycle for standard mounts.
[ ] Scoreboard still provides app shell rendering and shared-state construction for public/admin mounts.
[ ] Public and admin app entrypoints shrink to app decisions and mount config rather than duplicated lifecycle code.
[ ] Topic sync still follows loaded page state.
[ ] Dark-mode toggle behavior still works without app-owned storage/application mechanics.
[ ] Browser smoke passes for public navigation, admin navigation, dark mode, and broadcasts.

## Blocked by

None - can start immediately.
