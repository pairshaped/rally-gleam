---
# rally-rtld
title: Generate route load result adapters
status: completed
type: task
priority: high
tags:
    - boundary-cleanup
    - routing
    - load-rpc
created_at: 2026-06-05T18:00:00Z
updated_at: 2026-06-05T15:34:08Z
parent: rally-kobq
---

## What to build

Generate the browser and SSR load route/result adapters that Scoreboard currently hand-writes in `public_boot.gleam` and `admin_boot.gleam`.

Rally already generates much of the load transport. This slice removes the remaining authored route selectors and result-to-page-message adapters by consuming Proute page identity and page-owned load conventions.

## Current Scoreboard friction

- `public_boot.load_route` and `admin_boot.load_route` match generated routes to choose browser load requests.
- `public_boot.ssr_load_route` and `admin_boot.ssr_load_route` match generated routes to choose SSR loads and page-message wrappers.
- Public/admin boot modules map load results and load errors back into generated page messages by route.
- Root code still parses/carries route args that should be handled by generated Proute/Rally glue.

## Boundary constraints

- Rally consumes Proute route and page identity; it does not invent route aliases or page enums.
- Root routes are real pages. Any delegation from `home_.gleam` to another page is page-owned.
- Page behavior stays page-owned. Rally may generate mechanical wrappers around page load result conventions, but should not move product logic into root user modules.

## Acceptance criteria

- Scoreboard `public_boot.gleam` and `admin_boot.gleam` no longer contain route selectors for load dispatch.
- Generated Rally glue performs browser and SSR load selection from Proute output.
- Generated glue can wrap load success/error into generated Proute page messages without route-specific authored code.
- Clean regeneration and Scoreboard validation pass.

## Validation

- Rally build and focused load-rpc snapshots.
- Scoreboard regenerate with `gleam run -m rally load-rpc`.
- Scoreboard `gleam build --target erlang`, `gleam build --target javascript`, websocket smoke, and browser smoke.

## Summary of Changes

- Added generated browser and SSR load-route selection from Proute routes and load-owning page identity, including pages that alias `Model` and `Message` to the load-owning module.
- Generated result adapters now wrap load success/error into generated Proute page messages for browser websocket responses and SSR boot loads.
- Removed `select_load` parameters from generated app boot/load APIs.
- Added snapshot coverage for a home route delegating to another page and fixed local dependency paths for the renamed repo layout.
- Validation: `gleam format`; `gleam test --target erlang` (439 passed).
