---
# rally-sh4b
title: Move websocket topic registry plumbing into Rally
status: completed
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:17:33Z
updated_at: 2026-06-05T05:02:00Z
parent: rally-kobq
---

Scoreboard still has `app_topics.gleam` / `app_topics_ffi.erl` owning the websocket topic registry and self-excluded broadcast primitive. That is framework plumbing, not product behavior.

Current app-owned behavior that should stay in the app:

- choosing which topic(s) a connection joins
- deciding when a domain event should be broadcast
- building the broadcast payload/event
- selecting the broadcast module/topic identity if that remains product-specific

Framework behavior that should move into Rally:

- process-local topic registry lifecycle
- joining/leaving topics per websocket connection
- broadcasting to all members except the initiating connection
- mailbox message shape used to forward binary frames to websocket handlers
- small generated/runtime API for topic join and self-excluded broadcast

Acceptance criteria:

- Scoreboard no longer owns `app_topics.gleam` or `app_topics_ffi.erl` for generic topic registry mechanics.
- `app_ws.gleam` uses Rally runtime/generated topic APIs for join and broadcast-except-self.
- The origin connection is still excluded from broadcasts, while other connections on the same page/topic still receive the event.
- App-owned broadcast event mapping and timing remain in app code.
- Scoreboard websocket smoke tests pass.

Completion notes:

- Rally runtime topics now expose `broadcast_except_self` and `frame_selector`.
- Scoreboard removed `app_topics.gleam` and `app_topics_ffi.erl`.
- `app_ws.gleam` now uses `rally/runtime/topics` for topic startup, join, selector, and self-excluded broadcast.
- Scoreboard still owns the `"app"` topic choice, broadcast timing, and event construction.

Validation:

- Rally: `gleam build`
- Rally: `gleam test --target erlang -- --module rally/runtime/topics_test`
- Scoreboard: `gleam build --target erlang`
- Scoreboard: `gleam build --target javascript`
- Scoreboard: `gleam test --target erlang`
- Scoreboard: `node test/boundary_guard_test.mjs`
- Scoreboard: `node test/ws_result_smoke.mjs`
