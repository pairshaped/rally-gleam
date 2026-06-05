---
# rally-sh4b
title: Move websocket topic registry plumbing into Rally
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:17:33Z
updated_at: 2026-06-05T03:19:20Z
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
