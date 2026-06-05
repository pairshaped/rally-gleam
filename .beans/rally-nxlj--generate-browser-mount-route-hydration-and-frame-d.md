---
# rally-nxlj
title: Generate browser mount route, hydration, and frame dispatch
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:52Z
updated_at: 2026-06-05T12:00:00Z
parent: rally-kobq
---

`public_app.gleam`, `admin_app.gleam`, `public_boot.gleam`, `admin_boot.gleam`, and `to_client_application.gleam` still contain a large amount of standard browser plumbing: consuming Proute route/page output, initial load selection, hydration selection, navigation effect wiring, server-frame decoding, and generated page update mapping.

App-owned behavior that should remain authored:

- shell view and shared UI state values
- product navigation choices caused by page messages
- page-owned result-to-message behavior when it carries domain meaning
- broadcast event semantics and page update callbacks

Framework/generated behavior to move:

- browser app startup loop ceremony
- consuming Proute route values and page identity for current route state and page loading
- hydration helper selection by route/page
- client load request dispatch by route/page
- server-frame decode and mount-page dispatch
- navigation effect composition

Boundary constraints:

- Proute remains the only source of truth for route parsing, route params, query params, route values, and page dispatch shape.
- Rally must not generate a parallel route type, infer route aliases, or rediscover the page tree.
- Root routes are real pages. If `home_.gleam` delegates to another page's model/load/update/view, that delegation belongs in the page or a page-owned adapter.
- Do not drift into Lustre server-components architecture. Rally keeps browser TEA in the browser and sends typed domain messages, not DOM events or VDOM patches.

Acceptance criteria:

- Root browser modules shrink substantially or become small app callback/config modules.
- App code no longer manually switches over every route for hydration/load boilerplate.
- Generated browser glue consumes Proute-generated route/page identity instead of re-describing routing.
- Generated code does not absorb product-specific page update decisions without app callbacks.
- Clean regenerate and Scoreboard validation pass.
