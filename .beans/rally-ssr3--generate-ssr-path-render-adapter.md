---
# rally-ssr3
title: Generate SSR path render adapter
status: todo
type: task
priority: normal
tags:
    - boundary-cleanup
    - routing
    - ssr
created_at: 2026-06-05T18:00:00Z
updated_at: 2026-06-05T18:00:00Z
parent: rally-kobq
---

## What to build

Generate an SSR adapter that lets app-owned document rendering avoid route parsing and generated page dispatch.

Scoreboard's `app_ssr.gleam` should keep identity/auth context, shell choices, and app data dependencies. Rally/Proute generated glue should parse the path, normalize the current path, boot/load the page, select hydration payloads, and render or return the generated page output.

## Current Scoreboard friction

- `app_ssr.public_render` and `app_ssr.admin_render` parse paths into generated routes.
- `app_ssr` calls generated `route_to_path` helpers.
- `app_ssr` imports generated page modules to render page content.
- `app_ssr` passes route-aware boot selectors into generated SSR helpers.

## Boundary constraints

- App shell and identity policy are app-owned.
- Route parsing, page dispatch, load/hydration selection, and generated page view dispatch are generated glue.
- Rally consumes Proute output; it must not define its own route/page shape.

## Acceptance criteria

- Scoreboard `app_ssr.gleam` no longer imports generated route modules.
- Generated SSR adapter returns enough data for the app shell: page content, hydration payloads, and normalized current path.
- Public/admin SSR behavior and hydration remain unchanged.
- Clean regeneration and Scoreboard validation pass.

## Validation

- Rally build and SSR/load-rpc snapshots.
- Scoreboard `gleam build --target erlang`.
- Scoreboard Erlang tests and browser smoke for initial documents.
