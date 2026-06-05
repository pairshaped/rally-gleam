---
# rally-d4tc
title: Generate SSR route and document dispatch shell
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:52Z
updated_at: 2026-06-05T03:59:21Z
parent: rally-kobq
---

`app_ssr.gleam` still owns route parsing, route-to-load selection, page update invocation, and hydration composition. This is standard framework plumbing and violates the desired shape where routes are represented by file paths and generated Proute/Rally glue.

App-owned behavior that should remain authored:

- auth/session lookup and admin access policy
- document/shell rendering choices
- page-owned load functions and result-to-message callbacks where product-specific
- choosing what data is exposed in SSR boot attributes

Framework/generated behavior to move:

- public/admin route selection for SSR
- load handler dispatch from route values
- hydration payload selection
- applying page load messages during SSR
- composing Proute page output with Rally hydration helpers

Acceptance criteria:

- `app_ssr.gleam` no longer contains broad case expressions over generated route constructors just to choose load handlers.
- Generated Rally/Proute glue performs SSR route dispatch from generated route metadata.
- Application supplies only product callbacks/config needed by the generated shell.
- Clean regenerate and Scoreboard validation pass.



Progress slice: rally-7wan completed direct public SSR page load adapters. Generated server_ssr now calls page-owned public load_wire functions from configured load_context for String/Int route args, and Scoreboard app_ssr no longer owns public load handler callbacks. Route-to-message selection remains app-owned for now, so this bean stays open.
