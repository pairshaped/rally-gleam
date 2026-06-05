---
# rally-tzwk
title: Generate standard document boot glue
status: completed
type: task
priority: normal
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:57:07Z
updated_at: 2026-06-05T23:15:27Z
parent: rally-zmpm
---

## What to build

Move standard document response and boot mechanics behind Rally helpers or generated glue. Scoreboard should provide document content/layout decisions, while Rally owns response construction, query param extraction, hydration attribute encoding, boot data encoding, and browser entrypoint selection for the standard public/admin mounts.

## Acceptance criteria

[x] Rally owns content-type HTML response construction for standard SSR documents.
[x] Rally owns query-param extraction into generated Proute page_input values.
[x] Rally owns hydration data attribute encoding and escaping.
[x] Rally owns standard boot data attribute encoding for registered boot providers such as auth and dark mode.
[x] Rally owns browser entrypoint selection for generated mount bundles.
[x] Scoreboard app_document keeps only app document content and layout decisions, or disappears if those decisions move to a small app callback.
[x] Existing SSR snapshots and browser smoke pass.

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
