---
# rally-4aas
title: Make Rally migrate delegate to Marmot migrate
status: completed
type: feature
priority: high
created_at: 2026-06-06T13:46:24Z
updated_at: 2026-06-06T14:19:13Z
---

Rally currently has its own migration runtime path in `rally/runtime/migrate` and `rally migrate` calls it against a hard-coded `migrations` directory, then runs Marmot codegen. That conflicts with the Rally Scoreboard convention where Marmot owns configured database paths and migrations such as `db/migrations`.\n\nDecision:\n- Rally should not maintain a parallel migration system.\n- `rally migrate` should be a convenience CLI wrapper around Marmot migration behavior.\n\nScope:\n- Change `gleam run -m rally migrate` to delegate to `gleam run -m marmot migrate` using Marmot config.\n- Keep Marmot SQL codegen behavior where appropriate, either by relying on Marmot or explicitly running the same Marmot command sequence if needed.\n- Remove or deprecate Rally's parallel `rally/runtime/migrate` usage from the CLI and starter docs.\n- Decide whether `rally/runtime/migrate` remains as a runtime utility for legacy users or is deleted in a follow-up.\n- Update README, llms.txt, pages docs, scaffold README text, and tests so Rally migration docs point to Marmot-backed behavior.\n\nAcceptance:\n- In Rally Scoreboard, `gleam run -m rally migrate` applies migrations from the configured Marmot path, currently `db/migrations`.\n- No hard-coded `migrations` directory remains in the Rally CLI migrate path.\n- Tests cover that Rally migrate shells out to Marmot migrate or otherwise uses Marmot configuration.\n- Existing `rally build` and `rally gen` behavior stays compatible.

## Summary of Changes

`rally migrate` now delegates to `gleam run -m marmot migrate` when `[tools.marmot]` is configured, instead of opening SQLite and running Rally migrations against a hard-coded `migrations` directory.

The starter scaffold now writes migrations under `db/migrations`, matching Marmot defaults. README, llms.txt, configuration docs, runtime docs, scaffold README text, and tests were updated so app-facing migration behavior points to Marmot.

Validation: `gleam format` and `gleam test` passed with 189 tests.
