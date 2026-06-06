---
# rally-306z
title: Remove legacy JSON generated-client fixture coverage
status: completed
type: task
priority: normal
created_at: 2026-06-06T05:11:31Z
updated_at: 2026-06-06T05:14:23Z
parent: rally-536z
---

Remove fixtures/json_protocol and JSON generated-client tests once the old generated-client pipeline is no longer supported. Acceptance: gleam test passes without fixture .generated_clients builds or JS probes, and remaining JSON/Libero tests cover reusable lower-level code only.

## Summary of Changes

Removed the legacy json_protocol executable fixture, generated-client JSON integration test, and JS runtime probes that imported fixture .generated_clients output. Cleaned fixtures README. Validation: gleam format && gleam test, 436 passed.

## Summary of Changes

Removed fixtures/json_protocol and the generated-client JSON integration/runtime probes that consumed its .generated_clients output. Kept lower-level JSON generator unit tests for now because they belong to the remaining legacy generator modules. Validation: gleam format && gleam test, 436 passed.
