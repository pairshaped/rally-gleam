---
# rally-4xt9
title: Generate Rally browser runtime helpers during load-rpc
status: completed
type: task
priority: high
tags:
    - clean-regenerate
created_at: 2026-06-05T03:12:00Z
updated_at: 2026-06-05T03:16:02Z
---

Clean regeneration of the scoreboard example fails after deleting `src/generated` because `rally load-rpc` emits modules that import browser runtime helpers, but does not regenerate the helper files themselves.

Observed missing files after `rm -rf src/generated && gleam run -m rally load-rpc`:

- `src/generated/rally/browser.gleam`
- `src/generated/rally/browser_ffi.mjs`
- `src/generated/rally/browser_mount.gleam`
- `src/generated/rally/client_transport_ffi.mjs`

Acceptance criteria:

- `rally load-rpc` regenerates every Rally-owned file required by its generated modules.
- The regenerated browser helpers do not contain scoreboard-specific names.
- In the scoreboard example, deleting `src/generated` and rerunning Marmot, Proute, and Rally restores all required generated files.


Completed:

- `rally load-rpc` now emits the static Rally browser/runtime helper files required by generated load RPC modules.
- Generated browser helpers use Rally-neutral names (`data-rally-spa-nav`, `rally:to-server`, `__rallySocket`) and do not carry scoreboard-specific naming.
- Verified with Rally build/tests and a clean-regenerate pass in the scoreboard example.
