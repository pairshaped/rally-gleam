---
# rally-0jru
title: Move topic registry runtime into Rally
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:52Z
updated_at: 2026-06-05T03:18:52Z
parent: rally-kobq
---

This is the parent-epic version of `rally-sh4b`: `app_topics.gleam` and `app_topics_ffi.erl` own generic topic registry mechanics that should be Rally runtime/generated plumbing.

App-owned behavior that should remain authored:

- choosing topic names or topic identity
- deciding when to broadcast
- building the domain broadcast event

Framework/runtime behavior to move:

- topic registry process lifecycle
- joining/leaving topics for websocket connections
- self-excluded broadcast mechanics
- mailbox message shape for forwarding frames

Acceptance criteria:

- Scoreboard removes `app_topics.gleam` / `app_topics_ffi.erl` for generic topic mechanics.
- Origin connection is still excluded from broadcasts.
- Other connections subscribed to the same topic still receive broadcasts.
- Websocket smoke and topic tests pass.
