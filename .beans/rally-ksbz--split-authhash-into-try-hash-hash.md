---
# rally-ksbz
title: Split auth.hash into try_hash + hash
status: completed
type: task
priority: normal
tags:
    - auth
    - api
created_at: 2026-05-18T11:41:19Z
updated_at: 2026-05-18T14:45:37Z
---

`src/rally_runtime/auth.gleam:42-46` used `let assert Ok(hashes) = argus.hasher() |> argus.hash(...)`. Argus failures here are almost always deploy-time misconfiguration (bad NIF, OOM at the configured memory_cost), so forcing every caller to handle a Result they cannot recover from would just push the assert into every call site.

## Direction

- [x] Added `pub fn try_hash(secret: String) -> Result(String, argus.HashError)` for callers that want explicit handling.
- [x] Kept `pub fn hash(secret: String) -> String` as the convenience wrapper that calls `try_hash` and unwraps with `let assert`.
- [x] Same split for `hash_login_code` — `try_hash_login_code(scope, code) -> Result(String, argus.HashError)` returns the Argus error and keeps `hash_login_code` as the panic wrapper.
- [x] Documented `hash` and `hash_login_code` as panicking only on Argus misconfiguration; pointed at the `try_` variants for explicit handling.

## Out of scope

- Changing argus configuration defaults.
- Migrating call sites — `hash` and `hash_login_code` keep the same signatures, so existing callers (login, register, settings in the realworld example) are unaffected.

## Summary of Changes

`src/rally_runtime/auth.gleam`:
- Added `import gleam/result`.
- `hash` now reads `let assert Ok(hashed) = try_hash(secret:)` and returns `hashed`. The unwrap is unchanged in spirit but explicit about where it happens.
- New `try_hash(secret)` returns `Result(String, argus.HashError)` directly.
- `hash_login_code` and new `try_hash_login_code` mirror the same pattern.
- Updated docstrings on `hash` and `hash_login_code` to call out the panic condition (Argus misconfiguration only) and point at the `try_` variants for callers that want to observe failures.

`test/rally_runtime/auth_test.gleam`:
- `try_hash_returns_ok_on_normal_input_test` asserts the new API returns Ok, the hash has the expected `$argon2` prefix, and verify still works against the result.
- `try_hash_login_code_returns_ok_and_verifies_test` covers the scoped variant end-to-end.
- Did not add a failure-path test for `try_hash` because triggering an Argus HashError in unit-test conditions would require simulating NIF misconfiguration, which is exactly the situation the panic version was already failing on; integration coverage at that level is out of scope.

### Verification

- All 389 tests pass (was 387, +2 new try_hash tests).
- `gleam format --check` clean on both changed files.
- realworld example rebuilds clean (existing call sites use labeled args against `hash`, so unaffected by the new `try_` variants).

### API surface decision

Considered whether `hash` should be deprecated in favor of `try_hash`. Concluded no, per the review discussion: forcing Result handling on every call site for a deploy-time failure makes callers write `let assert Ok = hash(...)` themselves. Two functions, one opinionated for the common case, one principled for the rare one. Same pattern as Gleam stdlib's `int.parse` family.
