---
# rally-02qj
title: Generate or provide Rally HTTP server shell routing
status: todo
type: task
priority: normal
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:19:09Z
updated_at: 2026-06-05T12:00:00Z
parent: rally-kobq
---

`scoreboard_unified.gleam` still hand-writes standard server routing for static assets, websocket upgrade, public/admin SSR dispatch, and auth redirects. Some of this may remain app-owned during the chase, but the amount of standard plumbing is too high for a small app.

App-owned behavior that should remain authored:

- opening app resources such as the database
- session key policy and dev fallback
- authorization policy and custom access cases
- product redirects such as sign-in return paths

Framework/runtime behavior to consider moving:

- static asset route handling for generated JS/CSS assets
- websocket upgrade route wiring
- dispatching public/admin SSR routes by consuming Proute-generated route/page metadata
- standard session cookie and template-auth route plumbing where the app opts in
- standard server startup shell around a Rally app config

Boundary constraints:

- Proute owns route parsing and page shape. Rally's HTTP shell may call Proute-generated route helpers, but must not define its own route model.
- Authorization remains app-specific and callback-driven. Rally can own authentication plumbing and protected-route mechanics, but not product authorization decisions.
- Rally should stay a typed-domain-message framework, not a server-component runtime or VDOM patch server.

Acceptance criteria:

- Determine which root HTTP server responsibilities are truly Rally runtime concerns.
- Move standard routing/upgrade/static/SSR dispatch ceremony behind Rally APIs or generated code.
- Keep product authorization and resource initialization in app code.
- Scoreboard server behavior remains unchanged.
