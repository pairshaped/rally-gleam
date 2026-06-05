---
# rally-zmpm
title: Make Rally conventions own standard app glue
status: completed
type: epic
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T22:44:06Z
updated_at: 2026-06-05T23:37:34Z
---

Rally should make the standard template app feel framework-owned in the Rails sense: apps declare product meaning, while Rally owns repeated bootstrap, routing shell, document boot, browser lifecycle, websocket transport, static serving, and config mechanics.

Boundary decision:

The app cares about DB schema, layout, page views, page UI, page data, broadcast topics, broadcast events, and broadcast data. App code may also provide auth policy callbacks where the product cares: user lookup, role checks, route narrowing, and provider policy.

Rally should own framework mechanics around those authored surfaces: app/package metadata lookup from gleam.toml, PORT override parsing, DB path config and DB opening, auth session config, request/server context construction, HTTP routing shell, static serving, websocket transport, document boot/hydration mechanics, generated route/page dispatch, and repeated browser lifecycle ceremony.

Design rule:

If the code would be copied almost unchanged into another Rally template app, it belongs in Rally runtime or generated Rally glue. Authored root modules are acceptable only when they express a product decision.

References:

- Scoreboard ADR 0012: Use Convention Driven Rally App Surface

Current audit findings:

- src/admin_app.gleam and src/public_app.gleam duplicate browser lifecycle loops: model/message wrappers, init, update, server-frame handling, navigation, startup effects, and topic sync.
- src/app_document.gleam owns generic HTML response construction, query-param extraction, hydration data attributes, boot auth attribute encoding, and browser entrypoint selection.
- src/app_ws.gleam still owns Mist websocket message-loop ceremony, topic selector setup, topic cleanup, and custom-frame forwarding.
- src/app_ssr.gleam has one-field generated handler wrappers that could disappear if generated server_ssr accepts load_context directly.
- src/scoreboard_unified.gleam still owns standard server bootstrap, static routing, DB opening, auth session setup, and public/admin/websocket dispatch shell.
- src/app_config.gleam should disappear once Rally owns PORT/config bootstrap.
- src/page_stub.gleam is temporary projection scaffolding, not app behavior.

Acceptance criteria:

[x] Standard Scoreboard bootstrap no longer requires authored PORT parsing, DB path constants, DB opening, static asset routing, or auth session setup.
[x] Standard document response, query params, hydration attrs, boot attrs, and browser entrypoint selection are Rally-owned.
[x] Standard public/admin browser lifecycle is Rally-owned while app shell/shared-state decisions remain explicit.
[x] Standard websocket transport loop is Rally-owned while app load context, auth policy, and broadcast meaning remain explicit.
[x] Scoreboard root modules mostly express app-owned surfaces: auth policy, shell/layout, authentication context, broadcasts, page context if still needed, and page/domain code.
[x] Boundary guard, clean generation, browser smoke, websocket smoke, and Scoreboard tests pass.


## Completion audit

Root modules now keep the product-owned surface: auth policy callbacks, shell/layout, authentication context, broadcast topics/events/data, page context, page/domain code, and thin standard-entry callbacks that provide DB and authenticated-user context to Rally-owned glue.

Rally now owns the repeated standard app mechanics covered by this epic: bootstrap config and DB/session startup, static serving, document helpers, browser mount lifecycle, websocket transport loop, direct SSR load-context plumbing, and generated route/page dispatch around Proute output.

## Validation

- rally-gleam: `gleam test`
- rally-scoreboard-example: clean regeneration from empty `src/generated` with `gleam run -m marmot`, `gleam run -m proute`, and `gleam run -m rally load-rpc`
- rally-scoreboard-example: `gleam build --target erlang`
- rally-scoreboard-example: `gleam build --target javascript`
- rally-scoreboard-example: `node test/boundary_guard_test.mjs`
- rally-scoreboard-example: `TEMP=./tmp gleam test --target erlang`
- rally-scoreboard-example: `node test/ws_result_smoke.mjs`
- rally-scoreboard-example: `npm run test:browser`
