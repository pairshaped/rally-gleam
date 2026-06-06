---
# rally-2wgh
title: Evaluate Elm Land-style shared page context
status: completed
type: feature
priority: normal
created_at: 2026-06-06T01:24:27Z
updated_at: 2026-06-06T01:46:06Z
---

## Problem

Rally currently keeps client shared state at the generated mount/shell level. Pages receive `PageContext` and route/query inputs, but they do not receive the app's client shared state in the Elm Land style. Elm Land is an explicit inspiration for Rally's page model, so we should evaluate whether shared context should be available to page construction and selected page hooks.

## Intended Direction

Evaluate an Elm Land-style page construction shape where generated Rally/Proute glue can provide shared state and route context to pages, while pages choose whether to pass those values into init, update, view, topics/subscriptions, or other hooks. Do not blindly copy Elm Land; identify which ideas fit Rally's Gleam, SSR, generated-code, and target-split constraints.

## Acceptance Criteria

- [x] Document how Elm Land passes `Shared.Model` and `Route` into page construction and how pages opt into using them in hooks.
- [x] Audit Rally/scoreboard current `ClientSharedState`, `PageContext`, mount model, shell view, and generated page update flow.
- [x] Decide whether Rally should introduce a page-construction API, pass shared state to generated page dispatch, or keep shared state shell-only for now.
- [x] If adopting, implement the smallest slice that proves the API shape without forcing unrelated pages to depend on shared state.
- [x] Update ADRs with the intended design and non-goals.
- [x] Add focused tests/snapshots for whichever generator behavior is chosen.

## Summary of Changes

- Implemented a Rally browser mount adapter shape where `page_context` is derived from the latest mount shared state.
- Threaded derived `PageContext` through generated initial hydration application and page update dispatch.
- Parsed routes before browser mount initialization and navigation so shared state receives the canonical active path before page context is derived.
- Regenerated the scoreboard browser app glue and updated public/admin mount config callbacks to the new API.
- Updated Scoreboard ADR 0012 with the Elm Land-inspired design, the non-goal of passing whole shell shared state to pages, and the possible Proute ownership split.
- Added follow-up `rally-xdrl` for Proute page-construction ownership and `rally-otlr` for noisy expected formatter warnings in generator tests.
