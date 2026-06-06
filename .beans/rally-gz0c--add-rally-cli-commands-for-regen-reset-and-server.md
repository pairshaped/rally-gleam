---
# rally-gz0c
title: Add Rally CLI commands for regen, reset, and server restart
status: completed
type: feature
priority: normal
created_at: 2026-06-06T13:45:14Z
updated_at: 2026-06-06T14:24:52Z
---

Rally already has `gen`, `build`, and `migrate`, so the common workflow commands should live in Rally instead of app-local bin scripts.\n\nScope:\n- Add a `rally regen` command that deletes generated code under `src/generated` and then runs the normal generation pipeline.\n- Add a `rally reset` command that delegates to Marmot reset, so Marmot owns database paths, migrations, and seeds.\n- Add a `rally server` or `rally server restart` command that kills the existing app server for the configured/default port or stored pid, then starts a new server. Decide whether foreground or background is the default and document it.\n- Update CLI usage, README, llms.txt, and generated scaffold docs as needed.\n\nAcceptance:\n- `gleam run -m rally regen` removes stale generated files and regenerates Marmot/Proute/Rally/Libero output.\n- `gleam run -m rally reset` delegates to Marmot reset, including configured seeds.\n- Server restart behavior is deterministic and does not leave stale pid files.\n- Existing `gen`, `build`, and `migrate` behavior remains compatible.\n- Rally tests cover the new command routing and filesystem/process behavior where practical.



Update:
- `rally reset` should delegate to Marmot reset instead of hand-rolling drop/create/migrate.
- Marmot reset's seed step is acceptable and desired for the Rally app workflow.
- Do not create a separate Rally reset semantic unless Marmot changes its contract.

## Summary of Changes

Added `rally regen`, `rally reset`, and `rally server` / `rally server restart`.

`regen` deletes `src/generated` and runs the unified codegen path. `reset` delegates to `gleam run -m marmot reset`, including seeds. `server` stops any process listening on `PORT` from env/`.env` or 8080, then runs `gleam run` in the foreground without pid files.

The starter scaffold now includes `db/migrations` and an idempotent `db/seeds/001_counter.sql`, so Marmot reset works out of the box. README, llms.txt, scaffold README text, and downstream smoke coverage were updated.

Validation: `gleam format`, `git diff --check`, and `gleam test` passed with 189 tests.
