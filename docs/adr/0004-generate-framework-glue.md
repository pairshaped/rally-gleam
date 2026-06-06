# Generate Framework Glue

## Status

Accepted

## Decision

Rally owns repeated framework mechanics that would otherwise appear in every app
root module. Application modules should express product behavior.

Rally-generated glue owns:

- Browser boot and mount startup.
- Hydration payload decoding and application.
- Client WebSocket transport and request/result callback dispatch.
- Per-page load/save protocol wrappers.
- Server WebSocket request dispatch.
- SSR route rendering and boot data attributes.
- Page load effects and load result mapping.
- Browser navigation listeners and navigation effects.
- Topic sync and broadcast dispatch.
- Dark-mode runtime effects and storage mechanics.
- Standard app config/env parsing when the behavior is conventional.

Whole modules full of target annotations are framework glue when they only wrap
generated plumbing. User-owned modules should not exist solely to forward route,
load, hydration, browser navigation, or broadcast dispatch into generated code.

Generated Rally code should stay thin. Rally should not generate page UI,
domain rules, business decisions, SQL ownership, or a full client app from
server-shaped source. Client-side application behavior remains authored in
Gleam. JavaScript should be limited to small FFI modules around browser APIs.

## Consequences

Application roots become small. If code would be copied almost unchanged into
another Rally app, it belongs in Rally runtime or generated Rally glue.

App code still owns DB schema, layout, page views, page UI, page data, auth
callbacks, broadcast topics, broadcast events, and broadcast payloads.
