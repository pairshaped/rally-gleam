---
# rally-otlr
title: Quiet expected generated-code format warnings in tests
status: todo
type: bug
priority: low
created_at: 2026-06-06T01:44:45Z
updated_at: 2026-06-06T01:44:55Z
---

Rally generator snapshot tests intentionally fall back when `gleam format` cannot resolve target-project imports, but the green test run still prints repeated `gleam format failed` warnings. Keep the fallback behavior, but make expected test formatting failures quiet or scoped so real formatter failures stand out.
