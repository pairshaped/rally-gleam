---
# rally-0jru
title: Move topic registry runtime into Rally
status: completed
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:52Z
updated_at: 2026-06-05T05:02:00Z
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

Completion notes:

- Rally runtime owns the topic registry process lifecycle, join/leave, mailbox tag, frame selector, and self-excluded broadcast primitive.
- Scoreboard no longer owns a topic FFI module or a duplicate `pg` registry.
- The example now treats Rally as a runtime dependency because app/server code consumes Rally runtime topics.
- Product behavior remains app-owned: topic identity, when to broadcast, and which broadcast event to send.

Validation:

- Rally: `gleam build`
- Rally: `gleam test --target erlang -- --module rally/runtime/topics_test`
- Scoreboard: `gleam build --target erlang`
- Scoreboard: `gleam build --target javascript`
- Scoreboard: `gleam test --target erlang`
- Scoreboard: `node test/boundary_guard_test.mjs`
- Scoreboard: `node test/ws_result_smoke.mjs`
