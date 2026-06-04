---
# rally-utcl
title: Use a stable server-side effect runner
status: completed
type: task
priority: deferred
tags:
    - runtime
created_at: 2026-05-14T22:58:47Z
updated_at: 2026-06-04T23:00:18Z
---

Rally currently uses Lustre's @internal effect.perform in rally_runtime/internal/effect_runner.gleam, verified against Lustre 5.7.x. Track a stable alternative with the Lustre team or replace this with a supported API when available.



## Completion notes

No stable public Lustre replacement for `effect.perform` exists in the local Lustre 5.7 package. The practical fix here is to keep Rally and generated clients on the verified Lustre 5.x line until Lustre exposes a stable server-side effect runner.

Changes:

- Tightened Rally, generated client, scaffold, fixture, and RealWorld Lustre bounds to `>= 5.7.0 and < 6.0.0`.
- Added a generator test that protects the generated client Lustre 5.x bound.

Validation:

- `gleam build`
- `gleam test --target erlang` (425 passed)
