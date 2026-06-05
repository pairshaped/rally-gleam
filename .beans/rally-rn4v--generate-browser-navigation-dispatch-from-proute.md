---
# rally-rn4v
title: Generate browser navigation dispatch from Proute
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
    - routing
    - browser
created_at: 2026-06-05T18:00:00Z
updated_at: 2026-06-05T18:00:00Z
parent: rally-kobq
---

## What to build

Generate the browser navigation dispatch that Scoreboard currently hand-writes in `public_app.gleam` and `admin_app.gleam`.

Rally should consume Proute-generated route/page modules and expose browser helpers that let an app root respond to path changes and page navigation intents without matching generated route constructors, constructing generated routes, stringifying route params, or selecting page loads by route.

## Current Scoreboard friction

- `public_app.page_navigation` matches generated page-message wrappers and page-local navigation messages.
- `public_app.page_navigation` constructs `routes.TeamsSlug` and `routes.GamesId`, including route param stringification.
- Public/admin app roots call `routes.parse_path` and `routes.route_to_path` directly.
- Public/admin app roots pass route-aware load selectors into generated browser helpers.

## Boundary constraints

- Proute remains the only source of route/page shape.
- Rally must not rediscover routes or generate replacement route/page types.
- User-authored routing input remains the page filename/path layout.
- Page-owned navigation intent should stay page-local; generated glue may adapt it, but root user code should not maintain route/page dispatch.

## Acceptance criteria

- Generated browser helpers consume Proute route/page output directly.
- Scoreboard public/admin app roots no longer import generated route modules for navigation dispatch.
- Adding a page or changing a route does not require editing root browser app route cases.
- Browser navigation, shell navigation, initial load, and back/forward behavior remain unchanged.

## Validation

- Rally build and focused browser-app/load-rpc snapshots.
- Scoreboard regenerate with `gleam run -m rally load-rpc`.
- Scoreboard `gleam build --target javascript` and browser smoke.
