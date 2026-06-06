---
# rally-xdrl
title: Move Elm Land-style page shared state construction into Proute
status: completed
type: feature
priority: normal
created_at: 2026-06-06T01:45:35Z
updated_at: 2026-06-06T02:32:03Z
---

## Problem

Rally separated browser shell state from page-visible shared state, but generated page construction still had a `PageContext` membrane. The Elm Land-inspired responsibility is page construction: route identity, route params, query params, page model replacement, and which page hooks receive shared app state. That responsibility belongs in Proute because Proute owns route discovery, generated route params, generated page enums, and route-to-page dispatch.

## Decision

Use mount-owned page shared-state types as the page-visible shared input. Proute passes this input to generated page hooks as an opinionated convention 100 percent of the time. Rally consumes Proute output and builds the mount page shared state from browser boot facts or SSR request facts. Browser shell state remains private to the mount/shell, and server request/session/auth context stays distinct from page-visible shared state.

Default mount type names are convention driven:

- `public/page_shared_state.PublicPageSharedState`
- `admin/page_shared_state.AdminPageSharedState`
- `{mount}/page_shared_state.{PascalMount}PageSharedState` for other mounts

`page_shared_state_type` is a mount-level override only when an app keeps that type somewhere else.

## Acceptance Criteria

- [x] Audit Proute and Rally ownership boundaries for page construction, route params, query params, page enums, page update dispatch, topics/subscriptions, SSR `load_sync`, and browser load/init.
- [x] Decide the generated API name for page-visible shared state in a unified client/server source tree.
- [x] Implement the Elm Land-style convention that generated page construction passes page-visible shared state to page hooks consistently, with no per-page opt-in decision.
- [x] Decide how SSR/server construction obtains the same page-visible shared input without confusing it with server request context, session, DB context, or auth runtime context.
- [x] Implement the Proute/Rally generation path that passes page-visible shared state directly to generated page construction instead of adapting it through `PageContext` first.
- [x] Update Scoreboard public/admin app modules and all affected page modules so generated page APIs receive the new shared input directly everywhere.
- [x] Remove `PageContext` from generated page construction and page module APIs; pages receive the page-visible shared state directly.
- [x] Preserve route-param-backed topics/subscriptions and confirm dynamic page subscriptions still use route params instead of requiring duplicated model state.
- [x] Update ADR 0012 and Proute docs/ADR with the final ownership split and naming.
- [x] Add/update focused generator snapshots and Scoreboard compile/tests for Erlang and JavaScript.

## Validation

- Proute: `gleam format && gleam test` passed, 65 tests.
- Rally: `gleam format && gleam test` passed, 466 tests. Existing generated-code formatter warnings still appear under the known formatter-warning bean.
- Scoreboard: `gleam format && gleam test --target erlang && gleam test --target javascript` passed, 24 Erlang tests and 2 JavaScript tests.

## Non-goals

- Do not pass browser shell state into pages.
- Do not make Rally a second routing/page-construction framework.
- Do not use ambiguous names that collide with server context/session concepts in the unified source tree.
