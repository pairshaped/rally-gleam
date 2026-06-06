# Comparisons

Rally makes a specific set of architectural choices. This page explains those choices, what they cost, and how they compare to other approaches.

## Single Source

You write one Gleam project. Proute reads route files and produces route params, query params, page enums, and dispatch. Rally reads page contracts and produces browser boot, SSR, hydration, transport, topic sync, and load/save glue. Libero reads the same page-local server contracts and produces codecs and wire helpers.

The tradeoff: page modules carry more responsibility. Each authored page owns its client model, messages, load/save contract, and broadcast hooks until you extract shared code. The generated output is plain Gleam, so it is readable, but it is still code you did not write.

## Colocation-first

Types, state, and logic live in the page file until they need to be shared. There is no upfront shared domain layer. If two pages need the same type, extract it into a shared module at that point.

This is a bet that premature extraction costs more than occasional duplication. You'll sometimes have the same type defined in two places for a while before you notice and consolidate. That's fine. Extract when duplication becomes a maintenance problem, not before.

## SQLite ships with every app

Every Rally app gets SQLite with WAL mode, busy timeout, and foreign keys enabled. One embedded database, configured once in `db.open`. Development does not require a separate database process.

Marmot generates type-safe query functions from `.sql` files via live SQLite introspection. You write SQL, Marmot runs it against your actual schema, and generates Gleam functions with the correct argument and return types.

The joke version is: zero tradeoffs, you do not need anything more than `sqlite3`. The practical version is that SQLite removes a database service from local development and keeps deployment simple for many small and medium apps. Rally treats this as a framework convention. If another database should be supported, fork Rally and submit a tested PR instead of adding per-app framework glue.

## Lamdera-inspired

Lamdera's architecture is the starting point: explicit server handler types as the client-server contract, server-side state per connection, TEA on both sides. If you've used Lamdera, the shape of a Rally app will feel familiar.

Where they diverge: Gleam on the BEAM gives you OTP processes, `pg` groups, and native concurrency that Elm cannot access. Where the BEAM offers a better primitive, Rally uses it. Broadcast uses `pg` groups instead of custom fanout logic. Page-local save messages encode with native ETF instead of JSON. Libero handles typed request/result encoding instead of routing everything through a single update function.

## Rally vs Lustre server components

These are two different architectures for building full-stack apps with Lustre.

**Lustre server components** run the TEA loop on the server. Model, update, and view all execute server-side. On first connect, the server sends the current page's rendered DOM representation. On each update, it diffs the old and new view and sends only the patch. The client is a thin JavaScript shell that applies DOM patches and forwards browser events back to the server.

**Rally** runs TEA in the browser for UI state. Server work is explicit: pages call typed load/save handlers and subscribe to typed broadcast topics. The wire carries domain messages, not VDOM patches.

| | Lustre server components | Rally |
|---|---|---|
| **Where UI runs** | Server (model + update + view) | Client (model + update + view) |
| **What goes over the wire** | VDOM patches down, DOM events up | Domain messages in both directions |
| **Interaction latency** | Every event round-trips to server | Local state changes are instant |
| **Server memory** | Model + VDOM + event handler cache per running component instance | Request state, topic subscriptions, and app-owned resources. Page UI models live in the browser |
| **Client payload** | Thin DOM patcher JS plus the current page DOM on load | Full app logic (Lustre + page modules), with SSR HTML on first load |
| **Shadow DOM** | Component content renders in Shadow DOM, with open/closed shadow root config | Regular document DOM unless app code introduces a Shadow DOM boundary |
| **Shared live state** | Subscribed clients to the same running component receive the same patches. App routing/grouping decides who shares an instance | Explicit typed broadcast topics and per-connection subscriptions |

## When to use Lustre server components

To be honest? Most of the time.

For apps where interactions are button clicks, form submissions, and navigation, the server round-trip on same-region infra is often short enough that users will not notice it. The model is smaller: the server owns the TEA loop and the browser applies patches. When multiple clients subscribe to the same running component, they receive patches from the same server-side state.

Server components can also embed client-side Lustre components as web components when you need local interactivity. A server-rendered page can include a client-side rich text editor or drag-and-drop widget.

## When to use Rally

Rally fits when the browser needs to own more of the application behavior.

**Multiple client surfaces.** The server handler layer is a typed API contract. Web clients, CLIs, and SDKs can all call the same handlers. With server components, the wire protocol is VDOM patches, and only a browser can consume them.

**Responsive local interactions.** Typing with live feedback, drag-and-drop, rich editors, optimistic updates: anything where 10-50ms of server round-trip becomes perceptible. When state changes happen in the browser, the update does not wait for a request.

Rally asks more from you in exchange. Each page has a client update and (optionally) a server update. You decide which side owns each interaction. The browser ships more code up front, but that JavaScript is usually cached and long-lived. After that, Rally sends typed data messages that are often much smaller than VDOM diff patches. If your app has a single web frontend and interactions that tolerate a short round-trip, server components are the simpler path. If you need multiple client surfaces or local-first responsiveness, Rally's explicit message layer can be worth the extra code.
