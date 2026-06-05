---
# rally-tabm
title: Add explicit SSR route load adapter
status: completed
type: task
priority: high
tags:
    - codegen
    - ssr
created_at: 2026-06-05T01:15:56Z
updated_at: 2026-06-05T01:40:32Z
parent: rally-oymv
---

Remaining SSR route boot work from rally-i7ir.

Problem:
- Rally cannot infer every SSR route-to-load mapping from page-local wire contracts alone.
- Scoreboard represents public `Home` and `AdminHome` as real `home_.gleam` pages. Those root pages may delegate to games-page behavior, but that is page-owned behavior rather than a Rally alias convention.
- Guessing route aliases would make Rally absorb app/product route behavior and duplicate Proute-owned page shape.

Scope:
- Add an explicit page-owned declaration point for SSR route load behavior when Proute page identity is not enough.
- Generate the repetitive route boot/apply glue from those declarations.
- Keep shell rendering, auth/session identity, redirects, document metadata, and product-specific SSR decisions in app code.

Acceptance:
- App code no longer hand-writes repetitive SSR route load/apply boilerplate once the mapping is declared.
- Home/AdminHome behavior remains page-owned, not guessed by Rally as aliases.
- Generated code stays under `src/generated/rally/**`.
- Scoreboard SSR/browser smoke still passes.

Completed:

- Generated `server_ssr` mount boot helpers with explicit per-route load selector types and handler records.
- Kept root-page behavior explicit in `app_ssr` selector functions instead of inferring aliases.
- Moved domain load-to-wire and wire-to-message conversion into the page modules.
- Removed hand-written SSR hydration/apply/result-wrapper boilerplate from `app_ssr`.

Validation:

- Rally: `gleam build`
- Rally: `gleam test --target erlang -- --module rally/codegen_load_rpc_snapshot_test`
- Scoreboard: `gleam build --target erlang`
- Scoreboard: `gleam build --target javascript`
- Scoreboard: `gleam test --target erlang`
- Scoreboard: `node test/boundary_guard_test.mjs`
- Scoreboard: `node test/ws_result_smoke.mjs`
- Scoreboard: `node test/browser_smoke.mjs`
