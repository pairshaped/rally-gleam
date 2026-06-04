---
# rally-q304
title: Update SSR wire encoding
status: completed
type: task
priority: normal
tags:
    - wire
    - ssr
created_at: 2026-05-09T13:53:07Z
updated_at: 2026-06-04T19:16:59Z
---

Validation:
- This belongs in Rally, not Libero.
- `src/rally/generator/ssr_handler.gleam` still emits per-type `wire_encode_*` wrappers for client context and page flags when a wire module is configured.
- `src/rally.gleam` still passes `option.Some(config.wire_module)` to `libero.generate_dispatch` and to `ssr_handler.generate`.
- Page model seeds still look needed for generated JS decoders and `__wireAtom` metadata, so do not remove them without checking codec generation.

Dependency:
- Wait for Libero bean `libero-6vj3` to remove dispatch wire transform wrappers and settle the new Libero API.

Work:
- Update Rally to the new Libero dispatch API.
- Remove SSR-specific wire wrapper generation if `codec.encode_flags` can rely on the centralized `wire.encode` path.
- Keep page model seed discovery if JS decoder generation still needs it.

Acceptance:
- Rally builds against the updated Libero API.
- SSR flags and client context still encode with hashed wire atoms.
- Rally tests pass, then smoke test a route that renders SSR flags.



Completion notes:
- Removed ETF-only SSR `wire_encode_*` wrapper generation from Rally. SSR now relies on the generated protocol wire facade calling Libero `encode_flags`, which applies the registered Libero wire module transform on Erlang.
- Kept JSON SSR typed encoding intact, because JSON flags still need JSON codec values before `encode_flags`.
- Added a regression test that passes `wire_module: Some("generated@rpc_wire")` and asserts no `wire_encode_*` externals are emitted.
- Validation: `gleam format`, `gleam build --target erlang`, `git diff --check`, and broad `gleam test --target erlang router_snapshot` attempted. The test command still ran the broad suite; it reached 411 passed and failed only on the known JSON fixture missing `fixtures/json_protocol/build/packages/libero/gleam.toml`.
- Scoreboard currently has no generated SSR handler to smoke, so there was no app SSR route to exercise for this bean.
