---
# rally-yghe
title: Implement or hard-fail JSON client-context encoding
status: completed
type: bug
priority: high
tags:
    - codegen
    - json
created_at: 2026-05-18T11:41:04Z
updated_at: 2026-05-18T14:40:31Z
---

`src/rally/internal/generator/codec.gleam:548-551` emits a runtime panic for the JSON protocol path of `send_to_client_context`:

```
"\npub fn send_to_client_context(_msg: a) -> Effect(b) {\n"
<> "  panic as \"send_to_client_context: JSON client context encoding is not yet implemented\"\n"
<> "}\n"
```

A JSON-protocol app whose page calls `effect.update_client_context` (or anything that reaches this path) builds successfully and crashes at runtime, with no compile-time signal.

## Scope (hard-fail at codegen)

- [x] During `rally build`, detect any page contract that calls `send_to_client_context`.
- [x] If protocol is `json` AND at least one such page exists, surface a clear build error pointing at the page and mention the follow-up bean for the proper implementation.
- [x] If no page actually uses client-context updates, allow the build to continue (the runtime panic shim is dead code in that case, but stays as a backstop).
- [x] Regression test confirming the error fires under (json, page with `send_to_client_context`), and that no error fires under (json, no such page) or (etf, any).

## Out of scope

- Implementing the JSON encoding. Filed as `rally-au0s`.
- Removing the dead-code `panic` emission.

## Summary of Changes

`src/rally.gleam`:
- Added `check_json_client_context_compatibility_result(contracts, protocol) -> Result(Nil, String)` (pub for testability) and a private wrapper that maps the error into `RallyError`.
- Wired the check via `use _ <- result.try(...)` right before `codec.generate` in the per-namespace pipeline, so a failure surfaces as a normal `rally error: ...` with non-zero exit before any code is emitted.

### Why `string.contains` on page source, not the parser flag

The parser already tracks `updates_client_context: True` for pages whose `update` returns a 3-tuple including `Option(ClientContextMsg)`. But the realworld example's pages (login, register, settings) call `rally_effect.send_to_client_context` *inside an effect returned from a 2-tuple update*, which is not flagged by that bit. Pinning the guard to the parser flag would miss the most common usage path. Substring search on `contract.source` catches both shapes. False-positive risk (the symbol appearing only in a comment) is low and would only block a build that was about to crash at runtime anyway, so users would still be ahead.

`test/rally/json_client_context_guard_test.gleam` (new): four unit tests over the public entry point — ETF allows it, JSON without it is fine, JSON with it errors and names the offending page (plus the follow-up bean ID), JSON with multiple offenders reports each one and skips the clean pages.

### Verification

- All 386 tests pass (was 382, +4 new guard tests).
- `gleam format --check` clean on both changed files.
- realworld example (ETF) still regenerates and rebuilds clean.
- `fixtures/json_protocol` (JSON, no `send_to_client_context` in pages) still builds — guard correctly allows the clean case.

### Follow-up bean

`rally-au0s — Implement JSON encoding for client-context messages`. Once that lands, this guard becomes dead code; rather than removing it, the closure of `rally-au0s` should either delete the function or repurpose it as an assertion that the generated source contains no `panic as` for client-context.
