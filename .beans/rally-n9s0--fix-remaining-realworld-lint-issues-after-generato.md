---
# rally-n9s0
title: Fix remaining realworld lint issues after generator cleanup
status: in-progress
type: task
priority: high
created_at: 2026-05-09T13:52:32Z
updated_at: 2026-06-04T22:04:24Z
---

Context: After fixing 39 mechanical lint issues, 166 remain in realworld user code. Most need coordinated fixes in generators first.

Breakdown:
- 68 label_possible: Generator function params need labels first, then user code call sites updated
- 37 assert_ok_pattern: Intentional patterns; need architectural decision on error handling
- 30 unused_exports: False positives from generated/ exclusion; resolve when generated code is linted
- 17 thrown_away_error: Need result combinator refactoring
- 15 deep_nesting: Extract helper functions

Approach: Fix generator output to be lint-clean first, then update realworld user code to match. RealWorld is the only Rally consumer.



Progress 2026-06-04:
- Reproduced RealWorld lint at 188 errors.
- Fixed Rally-owned ETF rpc_dispatch field binding bug uncovered by RealWorld regeneration.
- Cleaned helpers/slug.gleam and its call sites; RealWorld lint is now 175 errors.
- Validation so far: Rally build passes; RealWorld migrate/build/regenerate/build passes; RealWorld slug tests pass; Rally scaffold_contract_test command is back to known JSON fixture failures only.



Progress 2026-06-04 continued:
- Cleaned register.gleam validation/session flow; remaining register warnings are generated-usage unused_exports only.
- Cleaned login.gleam validation/session flow; remaining login warnings are generated-usage unused_exports only.
- RealWorld lint is now 169 errors, down from 188 at the start of this pass.

Progress 2026-06-04 after fc09881:
- Cleaned settings.gleam validation/update/logout flow.
- Remaining settings warnings are generated-usage unused_exports only.
- RealWorld lint is now 167 errors.

Progress 2026-06-04 after 2d12303:
- Cleaned editor.gleam publish/tag-saving flow.
- Remaining editor warnings are generated-usage unused_exports only.
- RealWorld lint is now 160 errors.
