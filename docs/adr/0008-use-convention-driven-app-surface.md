# Use Convention Driven App Surface

## Status

Accepted

## Decision

Rally applications use strong framework conventions for the standard app shape.
The authored application describes product meaning. Rally owns repeated
bootstrap, transport, routing shell, document boot, and runtime mechanics.

The app-owned surface is:

- DB schema, migrations, seeds, authored SQL, and page data mapping.
- Layout, shell UI, page views, page UI state, and page update behavior.
- Page load/save behavior and the domain rules inside those handlers.
- Auth policy callbacks, user lookup/upsert, provider credentials, provider
  identity verification, and product-specific route narrowing.
- Broadcast topics, broadcast events, broadcast payload data, and page interest
  in those events.
- Page-level interpretation of route params when those params have domain
  meaning.
- Mount-owned page shared-state types that expose page-visible product facts,
  such as authenticated user data, authorization facts, and feature flags.

Rally owns the standard framework surface around that app code:

- App/package identity from `gleam.toml`.
- Process bootstrap for the standard template app.
- `PORT` override handling, parsing, fallback, and HTTP listener wiring.
- DB path config from `gleam.toml` with `DATABASE_PATH` override.
- DB opening and request/server context construction.
- Auth session secret config and generic session runtime mechanics.
- Standard auth provider route mechanics.
- Static asset serving conventions such as `/assets/` and `priv/static`.
- HTTP routing shell, public/admin mount dispatch, and fallback behavior.
- SSR document boot mechanics, hydration attributes, boot data encoding,
  browser entrypoint selection, and query-param extraction.
- Dark-mode first-paint mechanics and browser persistence. The generated theme
  helper treats `dark=1` as the only persisted dark-mode cookie value. Missing
  cookies or any other value use the light document theme on the server, while
  browser startup can still fall back to the device color-scheme preference
  before a user choice is persisted.
- Browser lifecycle ceremony: mount startup, current-path boot, page effect
  wiring, server-frame handling, navigation effects, browser navigation
  listeners, dark-mode runtime effects, and topic sync.
- Browser navigation policy. Rally wraps browser URL/navigation helpers such as
  Modem rather than exposing a broad same-origin interceptor as the app contract.
  The wrapper owns link eligibility, mount ownership, and server-owned route
  escape behavior before pushing browser history. Rally uses Modem for browser
  URL-change messages, while generated mounts keep silent history pushes for
  navigations they have already handled.
- WebSocket transport ceremony: upgrade handler shape, per-connection state
  threading, topic selector setup, topic joins/leaves, custom-frame forwarding,
  load/save dispatch, request/result encoding, and broadcast delivery.

Page shared state is passed to generated page hooks by convention 100 percent of
the time. There is no separate `PageContext` adapter layer. Browser mounts build
page-visible shared state from boot facts. SSR builds the same page-visible
shared state from request facts. Pages receive that shared state directly,
alongside generated route params and query params.

Rally should not pass browser shell state into pages. If a page needs a
shell-derived product fact, the app exposes that fact through mount page shared
state deliberately.

Rally should prefer intelligent defaults over app configuration. Configuration
exists only for values the app or deployment chooses.

## Consequences

Standard Rally apps contain less copied root-module code. The framework can test
the common path hard because there is one common path.

Application code remains explicit where the product has meaning.
