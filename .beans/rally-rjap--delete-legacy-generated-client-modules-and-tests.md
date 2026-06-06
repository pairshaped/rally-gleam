---
# rally-rjap
title: Delete legacy generated-client modules and tests
status: completed
type: task
priority: normal
created_at: 2026-06-06T05:11:31Z
updated_at: 2026-06-06T05:24:01Z
parent: rally-536z
---

Delete internal generator/client, codec, legacy router, SSR/HTTP/WS handler, dependency resolver, tree shaker, and legacy parser/scanner code that is no longer imported by unified Rally generation. Acceptance: no legacy generator modules or generated-client tests remain, and gleam test passes.

## Summary of Changes

Deleted the legacy generated-client modules, removed their tests and snapshots, and tightened scaffold contract tests around the unified generated files.

Validation: `gleam format && gleam test` passes with 190 tests.
