---
# rally-tabm
title: Add explicit SSR route load adapter
status: todo
type: task
priority: high
tags:
    - codegen
    - ssr
created_at: 2026-06-05T01:15:56Z
updated_at: 2026-06-05T01:15:56Z
parent: rally-oymv
---

Remaining SSR route boot work from rally-i7ir.

Problem:
- Rally cannot infer every SSR route-to-load mapping from page-local wire contracts.
- Scoreboard maps public Home to the games load through `public/pages/home_`, and AdminHome to admin games through `admin/pages/home_`.
- Guessing this from aliases would make Rally absorb app/product route behavior.

Scope:
- Add an explicit declaration point for SSR route load mappings, preferably in the page or route-owned authored code rather than a new app-wide registry module.
- Generate the repetitive route boot/apply glue from those declarations.
- Keep shell rendering, auth/session identity, redirects, document metadata, and product-specific SSR decisions in app code.

Acceptance:
- App code no longer hand-writes repetitive SSR route load/apply boilerplate once the mapping is declared.
- Home/AdminHome alias behavior remains explicit, not guessed by Rally.
- Generated code stays under `src/generated/rally/**`.
- Scoreboard SSR/browser smoke still passes.
