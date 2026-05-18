---
# rally-n0t8
title: Return an error on corrupted schema_migrations instead of silently resetting
status: completed
type: bug
priority: high
tags:
    - runtime
    - migrate
created_at: 2026-05-18T11:41:12Z
updated_at: 2026-05-18T14:43:06Z
---

`src/rally_runtime/migrate.gleam:121-127` handled the multi-row case by silently wiping the table and inserting `(last_migration: 0)`. On next startup all migrations re-run from scratch. The trigger is rare but the recovery is data-destructive and silent.

## Scope

- [x] Return a new `MigrationError` variant (`SchemaTableCorrupted`) instead of cleaning up.
- [x] Surface the error to the caller so app startup fails loudly rather than silently re-migrating.
- [x] Decide whether to keep any recovery helper as an explicit opt-in. _Did not add one. The error message tells the operator to inspect the table manually; a footgun "reset the migration history" helper invites accidental data loss. If a recovery utility is wanted later, it can be a separate `pub fn reset_schema_migrations` with a name that demands intent. Tracked implicitly — not opening a follow-up bean for it until someone asks._
- [x] Test: insert two rows into schema_migrations and assert `migrate.run` returns the new error variant.

## Summary of Changes

`src/rally_runtime/migrate.gleam`:
- Added `SchemaTableCorrupted(row_count: Int)` to `MigrationError`.
- `error_to_string` formats the variant with the actual row count and instructs the operator to resolve manually; explicitly tells them Rally will not silently reset.
- `get_current_version` query no longer uses `LIMIT 1`. This is load-bearing: the original `LIMIT 1` masked the corruption signal entirely — the third match arm was dead code, since SQLite only ever returned one row regardless of how many were in the table. Removing `LIMIT 1` lets the corruption case actually surface. Performance impact is nil because schema_migrations is expected to hold exactly one row.
- Replaced the silent `DELETE; INSERT (0)` cleanup with `Error(SchemaTableCorrupted(row_count: list.length(rows)))`.

`test/rally_runtime/migrate_test.gleam`:
- New `corrupted_schema_migrations_table_returns_error_test` seeds two rows into schema_migrations and asserts `migrate.run` returns `SchemaTableCorrupted(row_count: 2)`. This wouldn't have failed under the old code (because of `LIMIT 1` plus the silent reset both hiding it), so it's a genuine regression test for the new behavior.

### Verification

- All 387 tests pass (was 386, +1 corruption regression test).
- `gleam format --check` clean on both changed files.

### Note on the existing rollback test

`failed_migration_rolls_back_and_keeps_version_test` still passes unchanged — its setup never produces multi-row schema_migrations, so the behavior change is transparent.
