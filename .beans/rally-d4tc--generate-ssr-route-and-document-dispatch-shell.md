---
# rally-d4tc
title: Generate SSR route and document dispatch shell
status: in-progress
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:52Z
updated_at: 2026-06-05T04:45:53Z
parent: rally-kobq
---

`app_ssr.gleam` still owns too much SSR glue around route-to-load selection, page update invocation, and hydration composition. This is standard framework plumbing and violates the desired shape where Proute provides route/page shape and Rally composes SSR/hydration glue around it.

App-owned behavior that should remain authored:

- auth/session lookup and admin access policy
- document/shell rendering choices
- page-owned load functions and result-to-message callbacks where product-specific
- choosing what data is exposed in SSR boot attributes

Framework/generated behavior to move:

- consuming Proute-generated public/admin route and page identity for SSR
- load handler dispatch from route values
- hydration payload selection
- applying page load messages during SSR
- composing Proute page output with Rally hydration helpers

Boundary constraints:

- Proute owns route parsing, route params, query params, route values, page enums, and page dispatch shape.
- Rally consumes Proute output. It must not infer route aliases, generate route/page shape, or rediscover route files.
- Root routes are real pages. `Home` and `AdminHome` should be generated from `home_.gleam`; any delegation to games pages is page-owned behavior.
- Rally is not generating a Lustre server-component mount. SSR glue may render an initial document and hydration payload, but Rally must not introduce server-side VDOM state, DOM-event forwarding, or VDOM patch transport.

Acceptance criteria:

- `app_ssr.gleam` no longer contains broad case expressions over generated route constructors just to choose load handlers.
- Generated Rally glue performs SSR dispatch by consuming Proute-generated route/page metadata.
- Application supplies only product callbacks/config needed by the generated shell.
- Clean regenerate and Scoreboard validation pass.



Progress slice: rally-7wan completed direct public SSR page load adapters. Generated server_ssr now calls page-owned public load_wire functions from configured load_context for String/Int route args, and Scoreboard app_ssr no longer owns public load handler callbacks. Route-to-message selection remains app-owned until Rally can consume the Proute page identity and a page-owned load adapter without inventing aliases or product behavior.



Progress slice: Scoreboard moved the remaining SSR route-to-message callbacks out of app_ssr.gleam and into public_boot.gleam/admin_boot.gleam as page boot adapters. app_ssr.gleam now consumes generated/rally/server_ssr with app-owned callback functions and no broad route constructor switch. This does not complete the full generated document dispatch shell, but it removes the root SSR case noise without making Rally own page semantics.

Validated in Scoreboard with:

• gleam build --target erlang
• gleam build --target javascript
• node test/boundary_guard_test.mjs
• node test/ws_result_smoke.mjs

Validation caveat: Scoreboard gleam test remains blocked in this workspace by stale /tmp/scoreboard-unified-*.db files owned by debian.
