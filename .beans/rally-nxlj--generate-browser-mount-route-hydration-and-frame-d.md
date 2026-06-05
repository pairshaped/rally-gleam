---
# rally-nxlj
title: Generate browser mount route, hydration, and frame dispatch
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:52Z
updated_at: 2026-06-05T03:18:52Z
parent: rally-kobq
---

`public_app.gleam`, `admin_app.gleam`, `public_boot.gleam`, `admin_boot.gleam`, and `to_client_application.gleam` still contain a large amount of standard browser plumbing: route parsing, initial load selection, hydration selection, navigation effect wiring, server-frame decoding, and generated page update mapping.

App-owned behavior that should remain authored:

- shell view and shared UI state values
- product navigation choices caused by page messages
- page-owned result-to-message behavior when it carries domain meaning
- broadcast event semantics and page update callbacks

Framework/generated behavior to move:

- browser app startup loop ceremony
- current route parsing and route-to-page loading
- hydration helper selection by route/page
- client load request dispatch by route/page
- server-frame decode and mount-page dispatch
- navigation effect composition

Acceptance criteria:

- Root browser modules shrink substantially or become small app callback/config modules.
- App code no longer manually switches over every route for hydration/load boilerplate.
- Generated code does not absorb product-specific page update decisions without app callbacks.
- Clean regenerate and Scoreboard validation pass.
