---
# rally-nxlj
title: Generate browser mount route, hydration, and frame dispatch
status: done
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:18:52Z
updated_at: 2026-06-05T01:30:00Z
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



Progress slice: generated Rally browser app glue now consumes Proute mount route/page modules and emits per-mount `*_initial_page` and `*_load_client` helpers. The app supplies `load_route` callbacks that map route values to typed load result messages, so Rally owns hydration selection, client request dispatch, and route arg extraction without taking over product-specific result-to-message behavior. Scoreboard public/admin browser roots now call those generated helpers instead of hand-writing route-wide hydration and load request cases.

Validated with:

• Rally `gleam build`
• Scoreboard `gleam run -m rally -- load-rpc`
• Scoreboard `gleam build --target erlang`
• Scoreboard `gleam build --target javascript`
• Scoreboard `node test/boundary_guard_test.mjs`
• Scoreboard `node test/ws_result_smoke.mjs`

Final validation after restoring browser smoke:

• Scoreboard `gleam run -m rally -- load-rpc`
• Scoreboard `gleam build --target erlang`
• Scoreboard `gleam build --target javascript`
• Scoreboard `TEMP=/home/daverapin/projects/gleam/rally-scoreboard-example/tmp gleam test --target erlang`
• Scoreboard `node test/boundary_guard_test.mjs`
• Scoreboard `node test/ws_result_smoke.mjs`
• Scoreboard `npm run test:browser`

Acceptance status: complete. Browser app startup, hydration/load selection, route-arg extraction, navigation effect composition, and server-frame decode are generated Rally glue that consumes Proute output. Scoreboard root browser modules retain shell state, product navigation choices, and page/broadcast callbacks.

Validation caveat: Rally's test runner ignored the requested module filter and ran the wider suite; unrelated dependency/tmp failures remain. Scoreboard `gleam test --target erlang` is currently blocked in this workspace by stale `/tmp/scoreboard-unified-*.db` files owned by `debian`, because `test/support/test_db.gleam` hardcodes `/tmp`.



Progress slice: generated Rally browser app glue now decodes server frames itself when a push contract is configured. The generated `server_frame_effect` consumes `generated/rally/client_protocol.decode_server_frame` and calls an app-supplied typed push callback with the decoded module and broadcast payload. Scoreboard deleted the root `to_client_application.gleam` decode shim; public/admin boot adapters still own broadcast meaning and page update decisions.

Validated with:

• Rally `gleam build`
• Rally `gleam test --target erlang -- --module codegen_load_rpc_snapshot_test` enough to refresh `load_rpc_browser_app_gleam`; the command still runs unrelated wider tests and fails on known environment/downstream issues.
• Scoreboard `gleam run -m rally -- load-rpc`
• Scoreboard `gleam build --target erlang`
• Scoreboard `gleam build --target javascript`
• Scoreboard `node test/boundary_guard_test.mjs`
• Scoreboard `node test/ws_result_smoke.mjs`
