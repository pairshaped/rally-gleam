---
# rally-02qj
title: Generate or provide Rally HTTP server shell routing
status: todo
type: task
priority: normal
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:19:09Z
updated_at: 2026-06-05T03:19:09Z
parent: rally-kobq
---

`scoreboard_unified.gleam` still hand-writes standard server routing for static assets, websocket upgrade, public/admin SSR dispatch, and auth redirects. Some of this may remain app-owned during the chase, but the amount of standard plumbing is too high for a small app.

App-owned behavior that should remain authored:

- opening app resources such as the database
- session key policy and dev fallback
- auth endpoints and admin access policy
- product redirects such as sign-in return paths

Framework/runtime behavior to consider moving:

- static asset route handling for generated JS/CSS assets
- websocket upgrade route wiring
- dispatching public/admin SSR routes through generated route metadata
- standard server startup shell around a Rally app config

Acceptance criteria:

- Determine which root HTTP server responsibilities are truly Rally runtime concerns.
- Move standard routing/upgrade/static/SSR dispatch ceremony behind Rally APIs or generated code.
- Keep product auth and resource initialization in app code.
- Scoreboard server behavior remains unchanged.
