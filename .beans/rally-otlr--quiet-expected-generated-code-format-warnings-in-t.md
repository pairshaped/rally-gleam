---
# rally-otlr
title: Quiet expected generated-code format warnings in tests
status: completed
type: bug
priority: low
created_at: 2026-06-06T01:44:45Z
updated_at: 2026-06-06T03:14:27Z
---

Rally generator snapshot tests intentionally fall back when `gleam format` cannot resolve target-project imports, but the green test run still prints repeated `gleam format failed` warnings. Keep the fallback behavior, but make expected test formatting failures quiet or scoped so real formatter failures stand out.



## Resolution

Added `format_gleam_quiet` for expected formatter fallback paths in tests. Production codegen still uses `format_gleam` and still warns when formatter fallback happens. Snapshot helpers and the invalid-syntax fallback test now opt into quiet fallback, so green test runs no longer bury real warnings under repeated expected `gleam format failed` messages.

Validation: `gleam format && gleam test` passes with 466 tests and no generated-code format fallback warnings.
