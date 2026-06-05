---
# rally-df3o
title: Generate browser app boot wrapper
status: completed
type: task
priority: normal
tags:
    - codegen
    - browser
created_at: 2026-06-04T23:18:39Z
updated_at: 2026-06-05T01:25:28Z
parent: rally-oymv
---

Scoreboard public/admin browser modules still hand-author Rally browser boot plumbing. Generate or centralize the Lustre browser app wrapper so authored app modules only provide app-owned callbacks and shell/shared-state behavior.

Problem:
- Browser modules manually start Lustre apps.
- They manually parse routes and build startup effects.
- They manually apply hydration fallback and server frames.
- They manually wrap browser navigation into route load effects.

Scope:
- Generate a browser app adapter for each Rally app target, or generate enough helper surface that public/admin wrappers become app-owned shell configuration only.
- Keep app-owned shared state, shell rendering, auth UI, dark-mode state, and page view/update behavior in authored code.
- Reuse generated boot/hydration modules instead of duplicating route-load and broadcast-apply code.
- Preserve target-specific behavior for public and admin applications.

Non-goals:
- Do not generate page view functions.
- Do not generate app shell layout.
- Do not force one shared-state type across targets.

Acceptance:
- Scoreboard public/admin browser app modules no longer hand-write generic Rally startup, hydration fallback, frame apply, and navigation effect plumbing.
- Generated code remains under `src/generated/rally/**`.
- Existing public/admin browser behavior still works after regeneration.
- Tests or snapshots cover the generated browser boot shape.



Progress notes:
- Added generated `src/generated/rally/browser_app.gleam` for Lustre startup, common browser startup effects, and navigation effect batching.
- Scoreboard public/admin browser modules now call `browser_app.start`, `browser_app.startup_effects`, and `browser_app.navigation_effects` instead of hand-authoring those mechanics.
- Hydration fallback routing and server-frame application are still in authored public/admin modules, using generated `hydration`, `public_boot`/`admin_boot`, and `to_client_application` helpers. Those need another slice or an explicit route-load declaration boundary before more generation.



Completion notes:
- Added generated `browser_app.initial_page`, `browser_app.map_page_effect`, and `browser_app.server_frame_effect`.
- Scoreboard public/admin browser modules now delegate hydrate-or-load fallback and server-frame page-effect mapping to generated Rally code.
- Remaining route alias/load mapping is tracked separately in `rally-tabm`; those choices are app/product behavior until made explicit.
- Validation passed: Rally `gleam build`, focused load-RPC snapshot test, Scoreboard Erlang/JS builds, and browser smoke.
