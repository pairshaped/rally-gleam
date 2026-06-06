---
# rally-dn07
title: Update examples and smoke tests for unified build
status: completed
type: task
priority: normal
tags:
    - rally
    - tests
created_at: 2026-06-06T04:32:49Z
updated_at: 2026-06-06T05:06:51Z
parent: rally-ic6f
blocked_by:
    - rally-51ow
---

Goal: make Rally tests and examples validate the Rally Scoreboard build path instead of the legacy generated-client path.

Scope:
- Update downstream smoke tests to run `rally build` against a unified-source app shape.
- Add or reuse a Rally Scoreboard integration check from rally-gleam.
- Move RealWorld/generated-client JS tests under legacy coverage or mark them as legacy.
- Keep protocol-level tests where they still protect code that has not been deleted.

Acceptance:
- The main smoke path exercises Proute + Rally unified generation + Libero codec generation + app JS/Erlang builds.
- `.generated_clients` tests are explicitly legacy or removed.
- Test names and failure messages no longer imply generated clients are the normal build path.

Started example and smoke migration. Downstream scaffold smoke now runs rally build on the unified scaffold. Added Rally Scoreboard example build smoke. RealWorld and JSON generated-client tests/docs are labeled legacy and use legacy commands.

Completed example and smoke migration. Main downstream smoke runs rally build against the unified scaffold. Added Rally Scoreboard example rally build smoke. RealWorld, JSON fixture, and generated-client JS/Gleam tests are explicitly labeled legacy and use legacy commands where they invoke Rally. Validation: gleam format && gleam test, 471 passed.
