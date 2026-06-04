---
# rally-2gxm
title: Investigate generated-code warnings
status: completed
type: task
priority: normal
tags:
    - lint
    - codegen
created_at: 2026-05-15T13:34:00Z
updated_at: 2026-06-04T19:29:21Z
---

Glinter warnings in generated code are currently suppressed broadly in gleam.toml, especially label_possible and unnecessary_string_concatenation. Do a proper investigation instead of assuming all warnings are unavoidable.

Questions to answer:
- Which warnings come from Rally source generators versus generated output fixtures/snapshots?
- Which label_possible warnings are on private helpers that can safely use labelled parameters?
- Which warnings are caused by generated code needing stable public/unlabelled APIs?
- Which string-concatenation warnings can be fixed by changing generator source without making generated strings harder to read?
- Are there generated imports or references that can be made cleaner so downstream apps see fewer warnings?

Potential outcome:
- Narrow glinter ignores to only unavoidable generated-code patterns.
- Fix private helper signatures where no public API or generated output contract changes.
- Add focused tests/snapshots so warning fixes do not regress generated code.
- Document any warning classes that are intentionally ignored because generated code requires them.



Completion notes:
- Current configured glinter baseline dropped from 39 warnings to 28 warnings.
- Generator-area configured baseline dropped from 17 warnings to 10 warnings.
- Removed the broad `unnecessary_string_concatenation` ignore from `gleam.toml`; a no-ignore scan across `src` now reports zero warnings for that rule.
- Fixed mechanical generated-code-source warnings: labelled internal `load_rpc` calls, combined adjacent literal string concatenations in generator output shims, and simplified one `load_rpc` boolean branch.
- Fixed four small runtime auth `missing_labels` call-site warnings.
- Left `label_possible` ignored for now: no-ignore scan across `src` reports 105 hits, with 52 in generator areas. That needs the coordinated generator API/call-site cleanup described in `rally-n9s0`, not a casual config change.
- Validation: `gleam format`, `gleam build --target erlang`, `gleam run -m glinter -- --format json src`, and `git diff --check` passed. Broad `gleam test --target erlang` reached 414 passed / 3 failures; failures are in the JSON protocol fixture generated dispatch (`ServerIncrementBy(amount:)` without a bound `amount`) and are outside this lint-cleanup slice.
