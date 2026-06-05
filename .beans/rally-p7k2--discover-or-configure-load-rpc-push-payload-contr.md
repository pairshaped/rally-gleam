---
# rally-p7k2
title: Discover or configure load-RPC push payload contracts
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
    - codegen
created_at: 2026-06-05T04:12:00Z
updated_at: 2026-06-05T04:12:00Z
parent: rally-kobq
---

Rally load-RPC generation currently hardcodes the websocket push payload type as `broadcasts.Event`. That matches the scoreboard example, but it is app-specific knowledge inside Rally.

Goal:

- Rally should discover or accept explicit configuration for push payload contracts.
- Generated client/server protocol modules should import and encode the declared push payload type(s), not assume `broadcasts.Event`.
- Scoreboard can continue to use `broadcasts.Event`, but that choice should live in app-owned code or app configuration.

Acceptance criteria:

- `src/rally/internal/generator/load_rpc.gleam` no longer hardcodes `import broadcasts` or `broadcasts.Event`.
- The scoreboard example still receives and applies `BroadcastGameUpdated` push frames.
- Libero still owns codec generation for the push payload type.
- Clean regeneration and Scoreboard websocket smoke pass.
