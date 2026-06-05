---
# rally-kobq
title: Collapse remaining root-level framework glue in Scoreboard
status: todo
type: epic
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:22Z
updated_at: 2026-06-05T12:00:00Z
---

Scoreboard's root `src` directory still contains too much Rally/Proute framework glue for the size of the app. The authored application should mostly express pages, domain/session behavior, authorization policy, shell/style, and product decisions. Route and page shape should come from Proute output. Rally should consume that output with Libero-backed protocol glue and app-provided callbacks.

Current root modules that are suspicious or partly framework-owned:

- `admin_app.gleam` / `public_app.gleam`: browser TEA wrapper, current-route parsing, hydration selection, navigation, server-frame dispatch.
- `admin_boot.gleam` / `public_boot.gleam`: client load routing, result-to-page-message mapping, broadcast application.
- `to_client_application.gleam`: decoded server-frame dispatch into mount pages.
- `app_ssr.gleam`: SSR route selection and load handler routing.
- `app_ws.gleam`: websocket dispatch wrappers and topic joining.
- `app_topics.gleam` / `app_topics_ffi.erl`: topic registry plumbing.
- `scoreboard_unified.gleam`: HTTP route routing, websocket/static/SSR dispatch shell.
- `app_api.gleam`: mix of Rally push-frame encoding and app-owned broadcast event construction.

Goal:

- The only route shape authored by the app should be route file names and page-owned behavior.
- Proute generated code should own route parsing, route params, query params, route values, page enums, and page dispatch shape.
- Rally generated code should consume Proute output and own repetitive SSR/browser boot composition, websocket dispatch ceremony, server-frame dispatch ceremony, and transport/topic plumbing.
- App code should retain product decisions: authorization policy, shell view/style, domain load/save behavior, broadcast event meaning, and when broadcasts occur.
- Rally must stay Rally-shaped: browser TEA with typed domain messages. Do not generate Lustre server-component runtime code, DOM-event forwarding, server-side VDOM state, or VDOM patch transport.

Acceptance criteria:

- Root `src` loses the framework-only modules or reduces them to small app-owned callback/config modules.
- Clean regeneration from empty `src/generated` still works.
- Scoreboard builds, tests, SSR snapshots, boundary guard, and websocket smoke pass.

Progress:

- Child beans for browser boot, SSR composition, websocket dispatch, topic plumbing, push-frame encoding, static assets, and the HTTP server shell are complete.
- Scoreboard now keeps database/session setup, auth policy, shell rendering, page behavior, and broadcast meaning app-owned while Rally owns the repeated transport and framework shell glue.

Still blocked:

- Clean regeneration from empty `src/generated` failed on 2026-06-05 before Rally ran. `gleam run -m proute` treats page-local `wire.gleam` files under `src/public/pages/**` as page modules and reports missing `Model`, `Message`, `init`, `update`, and `view`.
- Proute currently has no documented ignore or exclude config for nested non-page modules. Moving Scoreboard's page-local wire modules would break the current Rally convention that `public/pages/foo/wire.gleam` belongs to `public/pages/foo.gleam`.
- Template auth remains in `rally-mhn4` and needs a product/framework decision before implementation.
