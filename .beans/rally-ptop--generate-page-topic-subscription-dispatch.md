---
# rally-ptop
title: Generate page topic subscription dispatch
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
    - topics
    - broadcasts
created_at: 2026-06-05T18:00:00Z
updated_at: 2026-06-05T18:00:00Z
parent: rally-kobq
---

## What to build

Generate/runtime-support page topic subscription dispatch so broadcast interest lives in page modules instead of root page-constructor matching.

Root broadcast payload types such as Scoreboard's `broadcasts.gleam` remain app-owned. Page interest in those payloads should be expressed by page-owned topic declarations or hooks. Rally transport should join and leave topics as the active page changes, and deliver decoded push payloads to the active page without root user code deciding page participation.

## Current Scoreboard friction

- `app_ws.on_init` joins every client to `"app"`.
- `public_boot.apply_broadcast` and `admin_boot.apply_broadcast` match generated page constructors to decide which page receives `BroadcastGameUpdated`.
- `apply_push` treats module `"app"` as the root broadcast routing layer.

## Boundary constraints

- Broadcast event shape and sender-side meaning are app-owned.
- Page subscription interest is page-owned.
- Rally owns topic transport mechanics, websocket joins/leaves, and decoded push delivery.
- Proute owns page identity; Rally should consume Proute output when updating subscriptions for the active page.

## Acceptance criteria

- Pages can declare or expose topic subscriptions in page-local code.
- Generated/runtime websocket glue joins initial page topics and updates topics on navigation.
- Broadcast senders can target domain/page topics instead of a universal `"app"` topic.
- Scoreboard root boot modules no longer match page constructors to decide broadcast delivery.
- Existing multi-tab convergence behavior remains, excluding the initiating connection for its own mutation.

## Validation

- Rally build and generated runtime tests.
- Scoreboard websocket smoke proving broadcast convergence.
- Browser smoke if active-page subscription behavior changes.
