---
# rally-nbue
title: Move standard websocket transport loop into Rally
status: todo
type: task
priority: normal
tags:
    - boundary-cleanup
    - conventions
created_at: 2026-06-05T22:57:23Z
updated_at: 2026-06-05T22:57:23Z
parent: rally-zmpm
---

## What to build

Move the standard Mist websocket transport loop into Rally runtime or generated glue. Scoreboard should not own topic selector setup, topic leave/sync mechanics, custom-frame forwarding, binary client-frame dispatch ceremony, or stop/continue handling for the standard app.

The app still owns broadcast topics, broadcast events/data, auth policy, and page load/save behavior.

## Acceptance criteria

[ ] Rally owns websocket init/handler/close ceremony for the standard template app.
[ ] Rally owns topic selector setup, join/leave sync, and cleanup on close.
[ ] Rally owns custom-frame forwarding and binary client-frame dispatch ceremony.
[ ] Scoreboard provides only app-specific callbacks or config: load context, auth context, and broadcast domain definitions.
[ ] Broadcast-except-origin behavior is preserved.
[ ] websocket smoke, boundary guard, and browser smoke pass.

## Blocked by

None - can start immediately.
