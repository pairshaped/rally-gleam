---
# rally-tzwk
title: Generate standard document boot glue
status: todo
type: task
priority: normal
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:57:07Z
updated_at: 2026-06-05T22:57:07Z
parent: rally-zmpm
---

## What to build

Move standard document response and boot mechanics behind Rally helpers or generated glue. Scoreboard should provide document content/layout decisions, while Rally owns response construction, query param extraction, hydration attribute encoding, boot data encoding, and browser entrypoint selection for the standard public/admin mounts.

## Acceptance criteria

[ ] Rally owns content-type HTML response construction for standard SSR documents.
[ ] Rally owns query-param extraction into generated Proute page_input values.
[ ] Rally owns hydration data attribute encoding and escaping.
[ ] Rally owns standard boot data attribute encoding for registered boot providers such as auth and dark mode.
[ ] Rally owns browser entrypoint selection for generated mount bundles.
[ ] Scoreboard app_document keeps only app document content and layout decisions, or disappears if those decisions move to a small app callback.
[ ] Existing SSR snapshots and browser smoke pass.

## Blocked by

None - can start immediately.
