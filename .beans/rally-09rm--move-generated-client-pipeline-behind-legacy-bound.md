---
# rally-09rm
title: Move generated-client pipeline behind legacy boundary
status: completed
type: task
priority: normal
tags:
    - rally
    - legacy
created_at: 2026-06-06T04:32:32Z
updated_at: 2026-06-06T05:03:09Z
parent: rally-ic6f
---

Goal: stop presenting the old generated-client/server_* pipeline as the normal Rally architecture.

Scope:
- Rename CLI commands/docs/tests around the old path to legacy terminology.
- Mark or move RealWorld and JSON protocol fixtures as legacy examples if they still depend on `.generated_clients`.
- Keep enough tests to avoid accidental breakage while the code still exists.

Acceptance:
- Top-level README, llms.txt, and guides describe Rally Scoreboard as the true path.
- Any `.generated_clients` references live only in legacy docs/tests/examples.
- New docs do not recommend `server_*`, `server_init`, or `server_update` as the default authoring model.

Started legacy boundary docs cleanup. README and llms.txt now teach the unified Rally Scoreboard page-local load/save surface. JSON protocol fixture is labeled as a legacy generated-client fixture.

Completed legacy-boundary cleanup. Top-level README and llms.txt now describe Rally Scoreboard unified-source authoring as the default. Legacy generated-client references are explicitly labeled in docs, fixtures, CLI comments, and dependency-resolver error text. Validation: gleam format && gleam test, 470 passed.
