---
# rally-wajg
title: Define route-derived page subscription convention
status: completed
type: feature
priority: normal
created_at: 2026-06-06T00:45:06Z
updated_at: 2026-06-06T01:12:24Z
---

## Problem

Most page subscriptions are likely to be known from the route before page data loads. Today a page can accidentally tie subscription interest to loaded data, which causes a temporary empty topic set during navigation, for example `unsub` before `sub:game:1`.

## Intended Direction

Rally should make route-derived subscription identity easy and conventional. Detail pages should be able to declare topics from normalized route identity before load results arrive, while app code still owns topic vocabulary and event data.

## Acceptance Criteria

- [x] Add Elm Land-style route context to generated page/topic plumbing so route-backed hooks can derive interest from route params.
- [x] Keep generated dynamic route params as strings for now; typed params are a later explicit Proute feature.
- [x] Document the convention in the relevant ADR.
- [x] Update the scoreboard detail page to avoid temporary `unsub` when navigating from `/games` to `/games/:id` after the plumbing exists.
- [x] Add or update browser smoke coverage for detail-page navigation topic frames.
- [x] Keep app-owned topic types in `broadcasts.gleam`; do not move topic vocabulary into Rally internals.

## Notes

Lustre's official routing example uses the `modem` companion package, parses the current `Uri` into an app-owned `Route` custom type, and stores that parsed `Route` in the model. Dynamic `post_id` is parsed with `int.parse`; parse failure becomes `NotFound(uri:)`. This supports the route-identity-in-model direction, but at the whole-route level rather than a loose `Option(Int)`. Rally/Proute already generates typed route values, so the framework convention should consider preserving normalized page identity/state rather than making each page rediscover it from loaded data.

## Design Note

Prefer an Elm Land-style page construction API if Rally/Proute can generate typed route params. The generated route layer should support string params by default and typed params such as `Int` when route metadata or conventions declare them. This lets route-derived hooks like topics use typed identity without forcing every page to manually parse common params.

## Summary of Changes

- Proute generated dynamic page variants now retain route params alongside page models and preserve those params across page updates and views.
- Rally generated browser topic/apply-push glue now pattern matches dynamic page route params and calls dynamic page `topics(route_params, model)`.
- Scoreboard dynamic public pages now derive game/team topic interest from route params instead of loaded data.
- ADRs document route-aware topic hooks, string route params as the generated default, and typed params as future explicit Proute work.
- Browser smoke coverage asserts `/games -> /games/1` sends `sub:game:1` without a temporary `unsub`.
