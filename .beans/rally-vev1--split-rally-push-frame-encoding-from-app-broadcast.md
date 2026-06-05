---
# rally-vev1
title: Split Rally push-frame encoding from app broadcast construction
status: todo
type: task
priority: normal
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:19:09Z
updated_at: 2026-06-05T03:19:20Z
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
