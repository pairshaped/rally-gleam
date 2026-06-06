---
# rally-l1eb
title: Remove legacy RealWorld generated-client example
status: completed
type: task
priority: normal
created_at: 2026-06-06T05:11:31Z
updated_at: 2026-06-06T05:13:11Z
parent: rally-536z
---

Remove or archive examples/realworld and its JS probes once Rally Scoreboard is the supported example. Acceptance: no examples/realworld .generated_clients references remain in active docs/tests; any retained historical notes are archived, not presented as runnable current coverage.

## Summary of Changes

Removed the legacy RealWorld generated-client example, its CLI, tests, snapshots, SQL, and generated-client JS probes. Removed active docs/test references to examples/realworld. Validation: gleam format && gleam test, 471 passed.
