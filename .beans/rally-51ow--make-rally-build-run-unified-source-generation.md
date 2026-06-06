---
# rally-51ow
title: Make rally build run unified source generation
status: completed
type: task
priority: high
tags:
    - rally
    - build
created_at: 2026-06-06T04:32:32Z
updated_at: 2026-06-06T04:39:58Z
parent: rally-ic6f
---

Goal: make `gleam run -m rally build` mean the Rally Scoreboard path.

Scope:
- Run Marmot when configured.
- Run Proute when `proute.toml` exists.
- Generate `src/generated/rally/**` and `src/generated/libero/**` using the load-RPC generator.
- Build the current package for Erlang and JavaScript.
- Keep the legacy generated-client path temporarily behind explicit legacy commands only.

Acceptance:
- Rally Scoreboard can run `gleam run -m rally build` instead of `gleam run -m rally load-rpc` plus manual builds.
- `rally build` does not write or build `.generated_clients`.
- Legacy generated-client behavior is no longer the default command.
- `gleam test` passes in rally-gleam, or any failures are documented as pre-existing/legacy-only.

\n\nCompleted: rally build now runs unified codegen/build, legacy generated-client commands are explicit, Rally Scoreboard build passes, and rally-gleam tests pass.
