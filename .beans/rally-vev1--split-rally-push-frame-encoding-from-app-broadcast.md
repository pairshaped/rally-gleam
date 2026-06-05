---
# rally-vev1
title: Split Rally push-frame encoding from app broadcast construction
status: completed
type: task
priority: normal
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:19:09Z
updated_at: 2026-06-05T04:12:00Z
parent: rally-kobq
---

`app_api.gleam` currently mixes Rally protocol framing (`server_protocol.encode_push`) with app-owned broadcast event construction (`game_updated_broadcast`). The event construction is application behavior; the push-frame encoding is Rally protocol glue.

App-owned behavior that should remain authored:

- querying the domain data needed for a broadcast
- constructing `broadcasts.Event`
- deciding the module/topic identity if product-specific

Framework/generated behavior to move:

- encoding a push event into a websocket frame
- any module/envelope details required by Rally's protocol

Acceptance criteria:

- App code no longer imports `generated/rally/server_protocol` just to frame broadcasts.
- App-owned broadcast construction remains readable and close to the domain workflow.
- Websocket broadcast behavior stays unchanged.

Completion notes:

- Generated `server_ws` now exposes `push_frame(module:, message:)`, keeping websocket push framing behind the generated Rally websocket adapter.
- Scoreboard removed the app-level `app_api.push` wrapper and now calls `server_ws.push_frame` from the broadcast workflow.
- Added a boundary guard so `app_api` cannot re-import `generated/rally/server_protocol` or recreate local push-frame helpers.
- Validation passed: Rally focused load-RPC snapshot test, Scoreboard Erlang build, boundary guard, and websocket smoke.

Remaining risk:

- Rally load-RPC generation still assumes the push payload type is `broadcasts.Event`. That was already true before this slice, but it is still app-specific knowledge inside Rally and should become discovered or configured before this boundary is considered clean.
