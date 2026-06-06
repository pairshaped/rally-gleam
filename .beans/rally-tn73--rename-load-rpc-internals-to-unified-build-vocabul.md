---
# rally-tn73
title: Rename load-rpc internals to unified build vocabulary
status: completed
type: task
priority: normal
tags:
    - rally
    - naming
created_at: 2026-06-06T04:32:32Z
updated_at: 2026-06-06T05:10:41Z
parent: rally-ic6f
---

Goal: stop exposing `load_rpc` as the conceptual name for the new Rally generator.

Scope:
- Rename public CLI/docs from `load-rpc` toward build/gen terminology.
- Rename internal modules/tests only when the API shape is settled enough to avoid churn.
- Preserve compatibility aliases if useful during transition.

Acceptance:
- User-facing docs no longer describe the main generator as `load-rpc`.
- Internal names either match the unified-source concept or are explicitly transitional.

Started vocabulary migration. Plan: move user-facing config/docs/CLI from load-rpc toward unified build/source terms while keeping old load_rpc config and load-rpc command as compatibility aliases.

Completed user-facing vocabulary migration. New scaffold/docs/examples use [tools.rally.context] and [tools.rally.push]. Parser accepts both new tables and legacy [tools.rally.load_rpc.*] tables. CLI usage no longer advertises load-rpc, while load-rpc remains a compatibility alias for unified generation. Top-level generator function names now use Rally source/unified vocabulary; internal load_rpc module is documented as transitional. Validation: gleam format && gleam test, 472 passed.
