---
# rally-bxhu
title: Rename broadcast topic hook to broadcast_subscriptions
status: completed
type: task
priority: normal
created_at: 2026-06-06T13:19:07Z
updated_at: 2026-06-06T13:23:17Z
---

Rename the Rally page broadcast-interest hook from `topics` to `broadcast_subscriptions` so page contracts avoid colliding with future Lustre/browser subscriptions and avoid the noun/verb ambiguity of `broadcast_topics`.

Acceptance:
- Generator detects/calls `broadcast_subscriptions`.
- Docs and snapshots use `broadcast_subscriptions`.
- Rally Scoreboard example page hooks are renamed.
- Formatting and relevant tests pass.



Completed:
- Renamed Rally page broadcast hook from topics to broadcast_subscriptions.
- Updated generator, docs, snapshots, Rally Scoreboard authored pages, tests, ADR references, and regenerated scoreboard Rally output.

Validation:
- rally-gleam: gleam format; gleam test
- rally-scoreboard-example: gleam run -m rally build; gleam format; gleam test; node test/boundary_guard_test.mjs
- stale old-hook scans clean.
