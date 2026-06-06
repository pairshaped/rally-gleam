---
# rally-unag
title: Generate Rally Scoreboard style scaffold
status: completed
type: task
priority: high
tags:
    - rally
    - scaffold
created_at: 2026-06-06T04:32:32Z
updated_at: 2026-06-06T04:58:13Z
parent: rally-ic6f
blocked_by:
    - rally-51ow
---

Goal: update `rally init` so new apps look like Rally Scoreboard, not the legacy generated-client scaffold.

Scope:
- No `.generated_clients` directories or build paths.
- Add `proute.toml` and Proute dev dependency/config as needed.
- Scaffold page shared-state modules, Proute page modules, unified Rally app boot, generated/rally handler calls, and standard build instructions.
- Do not scaffold `server_*` RPC handlers. Use page-local `load`, optional `handle`, `ServerMsg`, `topics`, and `apply_broadcast` patterns.

Acceptance:
- Fresh scaffold runs `gleam run -m rally migrate`, `gleam run -m rally build`, and `gleam run`.
- Scaffold smoke test covers both Erlang and JavaScript package builds.
- Scaffold README describes unified-source conventions only.

Implemented unified Rally Scoreboard style scaffold: proute mount, page shared state, app shell, public browser entrypoint, websocket wrapper, bootstrap server module, Marmot SQL setup, and load-rpc context config. Smoke now exercises rally build on the scaffold. Also fixed generator behavior so pages without a push contract do not need a topics function.
