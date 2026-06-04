---
# rally-tbnf
title: Generate server websocket dispatch adapter
status: todo
type: task
priority: high
tags:
    - codegen
    - websocket
created_at: 2026-06-04T23:18:08Z
updated_at: 2026-06-04T23:18:08Z
parent: rally-oymv
---

Scoreboard still hand-authors Rally-owned websocket transport plumbing in its app server. Generate the server websocket dispatch adapter from Rally page contracts and routing metadata.

Problem:
- The app manually decodes incoming client frames.
- The app manually dispatches load/save/page messages by constructor.
- The app manually correlates request IDs and sends result frames through Mist.
- Repeated load/save handlers wrap page `load` and `handle` functions with the same transport mechanics.

Scope:
- Generate the request decode and dispatch loop for Rally-managed page load/save/update messages.
- Generate request/result correlation and frame encoding/sending.
- Keep app-owned callbacks explicit: context construction, auth/session checks, page load/handle functions, and broadcast policy.
- Preserve the current ack-plus-broadcast pattern: the initiating connection receives the result payload through the ack; other connections receive broadcasts when app policy says so.
- Ensure the generated adapter can call app-owned broadcast hooks without broadcasting back to the initiating connection.

Non-goals:
- Do not generate app domain behavior.
- Do not generate broadcast event shapes or decide when a domain result should broadcast.
- Do not move Libero codec generation into Rally.

Acceptance:
- The Scoreboard app no longer hand-writes raw Rally request decode/result encode websocket dispatch for page load/save/update messages.
- App code still owns authorization and broadcast decisions.
- Generated code is under `src/generated/rally/**`.
- Targeted tests cover request dispatch, error result generation, and self-excluded broadcast behavior.
- Scoreboard builds for Erlang and JavaScript after regeneration.
