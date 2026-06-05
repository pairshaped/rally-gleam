---
# rally-kobq
title: Collapse remaining root-level framework glue in Scoreboard
status: todo
type: epic
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:22Z
updated_at: 2026-06-05T03:18:22Z
---

Scoreboard's root `src` directory still contains too much Rally/Proute framework glue for the size of the app. The authored application should mostly express pages, domain/auth/session behavior, shell/style, and product decisions. Routing and handler composition should come from file paths, generated page metadata, and app-provided callbacks.

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

- The only routing code authored by the app should be route file names and product-level authorization decisions.
- Rally/Proute generated code should own repetitive route selection, SSR/browser boot composition, websocket dispatch ceremony, server-frame dispatch ceremony, and transport/topic plumbing.
- App code should retain product decisions: auth, admin access policy, shell view/style, domain load/save behavior, broadcast event meaning, and when broadcasts occur.

Acceptance criteria:

- Root `src` loses the framework-only modules or reduces them to small app-owned callback/config modules.
- Clean regeneration from empty `src/generated` still works.
- Scoreboard builds, tests, SSR snapshots, boundary guard, and websocket smoke pass.
