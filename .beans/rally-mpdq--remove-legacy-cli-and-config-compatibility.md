---
# rally-mpdq
title: Remove legacy CLI and config compatibility
status: completed
type: task
priority: normal
created_at: 2026-06-06T05:11:31Z
updated_at: 2026-06-06T05:26:41Z
parent: rally-536z
---

After legacy examples and fixtures are gone, remove rally legacy-build, legacy-gen, load-rpc alias, [[tools.rally.clients]], and [tools.rally.load_rpc.*] compatibility. Acceptance: CLI help only advertises init, migrate, gen, and build; code search shows no legacy config references.

## Summary of Changes

Removed the `load-rpc` CLI alias, deleted `[tools.rally.load_rpc.*]` fallback parsing, and stopped preserving legacy Rally context config during scaffold initialization. Removed the remaining active test reference to `[[tools.rally.clients]]`.

Validation: `rg` found no legacy CLI/config references under `src` or `test`; `gleam format && gleam test` passes with 189 tests.
