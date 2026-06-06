---
# rally-su4f
title: Fix Rally full-review findings
status: completed
type: bug
priority: high
created_at: 2026-06-06T18:42:09Z
updated_at: 2026-06-06T18:42:19Z
---

Address the accepted code-review findings in Rally codegen: optional broadcast hooks, query-param preserving SPA navigation, save messages requiring handle, client request timeout messaging, and hydrated load effects.

## Summary of Changes

- Broadcast hooks are discovered per route module and default to no subscriptions/no effect when missing.
- SPA navigation preserves query params and pushes the full path including search.
- Save command constructors now require a page handle function.
- Generated client load/save requests time out after 30 seconds with page-level load/save errors.
- Hydrated Loaded updates preserve effects instead of dropping them.

## Validation

- gleam format
- git diff --check
- gleam test: 193 passed
- rally-scoreboard-example: gleam run -m rally build
- Imported generated client_transport_ffi.mjs with Node successfully.
