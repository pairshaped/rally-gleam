---
# rally-536z
title: Delete legacy generated-client pipeline
status: completed
type: feature
priority: deferred
tags:
    - rally
    - legacy
created_at: 2026-06-06T04:32:49Z
updated_at: 2026-06-06T05:45:13Z
parent: rally-ic6f
blocked_by:
    - rally-09rm
---

Goal: remove the old generated-client generator after the unified build, scaffold, docs, and tests no longer depend on it.

Scope:
- Delete or archive generated-client modules such as client package generation, tree shaking, dependency copying, legacy RPC dispatch-only paths, and `.generated_clients` fixture expectations when no longer needed.
- Remove legacy CLI commands once no supported example or test depends on them.
- Keep lower-level reusable pieces only if the unified generator actually imports them.

Acceptance:
- No `.generated_clients` references remain outside archived legacy docs/history.
- No user-facing `server_*`/stateful page model remains in Rally docs.
- `gleam test` passes without generated-client fixtures.

Converted to a feature container because deleting the legacy generated-client pipeline needs multiple reviewable child tasks.

## Summary of Changes

Deleted the legacy generated-client pipeline, fixtures, examples, snapshots, tests, CLI/config compatibility, and user-facing docs. Replaced the auth codegen check with a unified Rally Scoreboard style smoke and trimmed stale runtime effect/stateful-server APIs.

Validation: stale-term `rg` scan is clean; `bin/check-auth-codegen` passes; `gleam format && gleam test` passes with 189 tests.
