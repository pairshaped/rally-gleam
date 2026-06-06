# Rally Auth Framework Design

Status: intended design, partially implemented runtime support
Date: 2026-05-10
Last checked: 2026-06-06

## Problem

Rally apps need a convention for authentication and authorization that works
across SSR page loads, browser navigation, page-local saves, and WebSocket
broadcasts. App code should define identity and policy; Rally should call those
hooks consistently without inspecting app domain types.

Current Rally exposes runtime auth helpers and generated mount auth checks. The
full `auth.gleam` discovery flow, identity-threaded page handler signatures,
`derive_state`, and per-page `authorize` plumbing described below are intended
design. Do not treat this document as the current generated app contract.

## Design

### Convention-Based Auth Module

Each mount may have an `auth.gleam` at its root. Rally scans for it during codegen and generates handler plumbing that calls into it.

```
src/admin/auth.gleam     → admin mount auth
src/public/auth.gleam    → public mount auth
```

If no `auth.gleam` exists for a mount, rally generates handlers without auth.

### Auth Module Contract

The auth module must export:

| Export | Signature | Purpose |
|--------|-----------|---------|
| `Identity` | type | App-defined identity type. Opaque to rally. |
| `resolve` | `fn(LoadContext, String) -> Result(Identity, Nil)` | Resolves session_id into an identity. Returns `Ok(Anonymous)` for missing/expired sessions, `Error(Nil)` for infrastructure failures. `resolve` logs its own error details before returning `Error`. |
| `is_authenticated` | `fn(Identity) -> Bool` | Rally calls this for `Required` pages to decide whether to redirect. |
| `redirect_url` | `String` | Where to redirect unauthenticated users. |

Rally imports the app's `Identity` type and threads it through to page functions. Rally never inspects the type's structure.

**Error handling:** `resolve` returns `Result(Identity, Nil)`. `Ok` with an unauthenticated variant (e.g., `Anonymous`) is a normal "no session" state. `Error(Nil)` signals an infrastructure problem (DB unavailable, token verifier broken). The app's `resolve` function is responsible for logging error details (it knows the error type and context). Rally returns HTTP 500 on `Error` with a generic "auth service unavailable" message. It never silently downgrades a broken auth check to "logged out."

### Interaction with Session-Derived State

The auth flow can derive page shared state and an enriched load context from the
session after identity is resolved. Auth's `resolve` handles identity; the
session-derived state hook handles everything else (org resolution, theme,
translations, tenant scoping).

**Ordering:** `resolve` runs first, then `is_authenticated` check, then the
session-derived state hook enriches `LoadContext`, then `authorize` runs with
the enriched context:

```
resolve(load_context, session_id) → Result(Identity, Nil)
  → Error: return 500
  → Ok(identity):
    → if Required and !is_authenticated(identity): redirect to redirect_url
    → derive_state(load_context, session_id, hostname, identity)
      → #(page_shared_state, enriched_load_context)
    → if authorize exists: authorize(enriched_load_context, identity)
      → False: 403
    → load(enriched_load_context, route_params..., identity) → LoadResult
```

The session-derived state hook receives `identity`. It can populate
identity-related `PageSharedState` fields (email, role, dark mode preference,
etc.) without re-looking up the session.

**Why authorize runs after state derivation:** `authorize` may need `org_id` or
other tenant-scoped data on `LoadContext` for row-level permission queries.
Running `authorize` before state derivation would give it an un-enriched
context.

### Page-Level Auth Declaration

Pages declare their auth requirement via a constant:

```gleam
pub const page_auth = rally.Required   // must be authenticated
pub const page_auth = rally.Optional   // resolve runs, page loads either way
// omitted = same as Optional
```

The constant is named `page_auth` (not `auth`) to avoid colliding with the app's auth module import. The values `rally.Required` and `rally.Optional` come from the rally package.

**What Optional means:** Optional skips the `is_authenticated` redirect check. It does NOT skip `authorize`. If a page is Optional and exports `authorize`, anonymous users reach the authorize check (since they pass the "no is_authenticated gate" step), and authorize decides whether they can proceed. This lets pages like "spares contact info" be Optional (anonymous users see a limited view) while still using authorize to gate specific content for members.

### Page-Level Authorization

Pages that need role or category-level access control export an `authorize` function:

```gleam
pub fn authorize(
  load_context: LoadContext,
  identity: Identity,
) -> Bool
```

`authorize` is a page gate: "Can this type of user access this area at all?" It checks roles, org membership, or user categories. It does not check resource-specific permissions (e.g., "can this user access item #5?").

Rally calls `authorize` after `derive_state` for pages that export it. Returns `False` = 403 or redirect. This applies to both Required and Optional pages: if `authorize` exists and returns `False`, access is denied regardless of auth policy.

Pages without `authorize` are accessible to any authenticated user (Required) or anyone (Optional).

`authorize` receives the enriched `LoadContext` (with org_id set) so apps can run tenant-scoped queries (e.g., check org membership).

### Resource-Level Authorization

Resource-specific permission checks (e.g., "does this EventManager have access to event #5?", "has this member purchased product #3?") happen in `load` and page handlers, not in `authorize`. These functions have access to route params (from the URL for `load`) or message fields (for page handlers), plus identity and load context.

```gleam
// src/admin/pages/registration/events/id_/registrations.gleam

// Page gate: any admin with item-management capability
pub fn authorize(load_context, identity) -> Bool {
  case identity {
    Admin(access: FullAccess, ..) | Admin(access: ItemManager(..), ..) -> True
    _ -> False
  }
}

// Resource check: this specific event (id from route)
pub fn load(load_context, id: Int, identity) -> LoadResult(Data) {
  case identity {
    Admin(access: ItemManager(permissions), ..) ->
      case has_item_permission(permissions, id, Registrations) {
        True -> // load data
        False -> Redirect("/admin", [])
      }
    Admin(access: FullAccess, ..) -> // load data
    _ -> Redirect("/admin", [])
  }
}
```

This separation keeps `authorize` simple (one signature, no route params, works identically across SSR, WebSocket, and HTTP save handling) and puts resource-level checks where the resource identity is naturally available.

### Load Result Type

Load handlers return `LoadResult(data)` which supports page data, redirects, and cookies in a single type:

```gleam
pub type LoadResult(data) {
  Page(data: data, cookies: List(Cookie))
  Redirect(url: String, cookies: List(Cookie))
}
```

**Page:** normal page load with optional cookies (most pages return `Page(data, [])`)
**Redirect:** server-side redirect with optional cookies (auth callbacks, logout, dev_login)

Rally's generated SSR handler pattern-matches on the result:
- `Page` -> render the page, apply cookies to the HTTP response
- `Redirect` -> return HTTP 302, apply cookies, no rendering

```gleam
pub type Cookie {
  SetCookie(name: String, value: String, max_age: Int)
  ClearCookie(name: String)
}
```

### Generated SSR Handler Behavior

```
HTTP GET → extract session_id from cookie
  → auth.resolve(load_context, session_id)
    → Error: return 500, log error
    → Ok(identity):
      → if Required and !is_authenticated(identity): redirect to redirect_url
      → derive_state(load_context, session_id, hostname, identity) → #(page_shared_state, enriched_sc)
      → if authorize exists and !authorize(enriched_sc, identity): 403
      → load(enriched_sc, route_params..., identity) → LoadResult
        → Page(data, cookies): render page, apply cookies
        → Redirect(url, cookies): HTTP 302, apply cookies
```

`identity` is appended after route params in `load`. Load context comes first, matching the Rally Scoreboard convention: `load(load_context, id, identity)` for dynamic pages, `load(load_context, identity)` for static pages.

### Generated HTTP Save Handler Behavior

HTTP save requests follow the same auth flow as SSR, run per-request:

```
HTTP save request → extract session_id from cookie → parse page message
  → auth.resolve(load_context, session_id)
    → Error: return 500
    → Ok(identity):
      → determine owning page module (rally knows this at codegen time)
      → if Required and !is_authenticated(identity): return 401
      → derive_state(load_context, session_id, hostname, identity) → #(_, enriched_sc)
      → if authorize exists on owning page:
        → authorize(enriched_sc, identity): False → 403
      → dispatch to page handle_save with enriched_sc and identity
```

Each save request is stateless: resolve and derive_state run on every request. The owning page module is known at codegen time because each `handle_save` belongs to exactly one page module.

### Generated WS Handler Behavior

**On upgrade (HTTP layer):**

The upgrade always proceeds. Auth is page-level, not namespace-level: a namespace with `auth.gleam` can still have Optional pages. Rejecting at upgrade time would block anonymous access to Optional pages.

```
HTTP upgrade request → extract session_id and hostname from request
  → resolve(load_context, session_id)
    → Error: reject upgrade with HTTP 500
    → Ok(identity):
      → derive_state(load_context, session_id, hostname, identity) → #(page_shared_state, enriched_sc)
      → proceed with upgrade
      → store identity + enriched_sc + page_shared_state + hostname + auth_timestamp on connection state
```

`resolve` errors reject the upgrade (infrastructure failure, not an auth policy decision). Page-level auth (Required/Optional, authorize) is NOT checked at upgrade time.

`derive_state` runs at upgrade time because the HTTP Host header (needed for org/tenant resolution) is not available after the WebSocket handshake. The hostname is stored on connection state so reauth can re-run `derive_state` later. The enriched LoadContext and PageSharedState are stored on connection state and used for all subsequent auth checks and save dispatch.

**On page navigation (page-init frame):**

Auth is checked against the candidate page *before* updating connection state. If auth fails, the current page remains unchanged, avoiding inconsistent state for subsequent save dispatch.

```
page-init frame → parse candidate page + route params (do NOT update connection state yet)
  → if Required and !is_authenticated(identity): send auth-redirect frame, keep current page
  → if authorize exists on candidate page:
    → authorize(enriched_sc, identity)
    → False: send auth-failure frame, keep current page
  → auth passed: update current page + route params on connection state
```

Page-level auth policy is enforced at navigation time, not upgrade time. This is where `Required` vs `Optional` matters for WebSocket connections.

**On save message:**

Save auth uses the **owning page** (determined by the decoded message type at codegen time), not the current page from connection state. This prevents a client on an Optional page from calling handlers on a Required page.

```
on_message:
  → if (now - last_auth_check) > reauth_interval:
    → re-resolve identity, update connection state
    → re-run derive_state(load_context, session_id, stored_hostname, identity)
      to refresh enriched_sc and page_shared_state (role, org membership, theme may have changed)
  → decode save message → determine owning page (codegen-known, from message type)
  → verify owning page matches current page (reject if mismatch)
  → if Required on owning page and !is_authenticated(identity): send auth-redirect frame
  → if authorize exists on owning page:
    → authorize(enriched_sc, identity)
    → False: send auth-failure frame
  → dispatch to page handle_save with enriched_sc and identity
```

**Why owning page, not current page:** rally knows at codegen time which page module defines each `handle_save`. The message type maps to exactly one page. Using the current page from connection state would be unsafe: a malicious client could navigate to an Optional page, then send frames targeting handlers on Required pages. By checking the owning page, the auth policy of the handler's actual page always applies.

**Why verify current page matches:** in rally's model, saves are contextual to the current page. A client should not send page messages for a page they're not on. Mismatches indicate a bug or a malicious client and are rejected.

**Reauth refresh:** when reauth triggers, both `resolve` and `derive_state` re-run. This ensures the connection state reflects current reality: role changes, org membership changes, theme updates, etc. This is slightly more expensive than re-resolving identity alone, but only happens every 30 minutes.

**Reauth interval:** default 30 minutes. No timers, no polling. One integer comparison per incoming message. Only re-resolves when the interval has elapsed.

### Page Handler Signatures

When auth.gleam exists, page handler signatures gain `identity`:

```gleam
pub fn handle_save(
  load_context: LoadContext,
  message: ServerMsg,
  identity: Identity,
) -> Result(response, error)
```

Identity is threaded to every page handler. The handler can use it for business-level authorization or ignore it if the page-level policy is sufficient.

### Codegen Discovery Changes

During codegen, Rally checks each mount for:

1. `auth.gleam` exists at the mount root
2. If yes, verify it exports: `Identity` (type), `resolve` (fn), `is_authenticated` (fn), `redirect_url` (const)
3. For each page module, check for `pub const page_auth` declaration and optional `pub fn authorize`
4. Generate handler code accordingly

Missing exports from auth.gleam should produce a clear codegen error.

### Page Function Signature Changes

When auth.gleam exists for a mount, page function signatures change:

**Without auth:**
```gleam
// Static page
pub fn load(load_context: LoadContext) -> Data

// Dynamic page (e.g., events/id_.gleam)
pub fn load(load_context: LoadContext, id: Int) -> Data
```

**With auth:**
```gleam
// Static page
pub fn load(load_context: LoadContext, identity: Identity) -> LoadResult(Data)

// Dynamic page (e.g., events/id_.gleam)
pub fn load(load_context: LoadContext, id: Int, identity: Identity) -> LoadResult(Data)
```

Rally appends `identity` after route params. Page models receive identity-derived data through page shared state or loaded page data. The `view` function signature does not change.

This is also where resource-level authorization happens. A dynamic page's `load` has the route params (e.g., `id`) and can check resource-specific permissions before loading data:

```gleam
pub fn load(load_context: LoadContext, id: Int, identity: Identity) -> LoadResult(Data) {
  case check_item_permission(load_context, identity, id) {
    True -> Page(load_data(load_context, id), [])
    False -> Redirect("/admin", [])
  }
}
```

## Implementation Checklist

1. Define `rally.Required` and `rally.Optional` constants, `LoadResult` type, `Cookie` type
2. Codegen: detect auth.gleam per mount, parse exports (Identity, resolve, is_authenticated, redirect_url)
3. Codegen: detect `pub const page_auth` and optional `pub fn authorize` on page modules
4. SSR handler codegen: resolve → is_authenticated check → derive_state(identity) → authorize(enriched_sc) → load ordering
5. SSR handler codegen: process LoadResult (Page vs Redirect, apply cookies)
6. HTTP save handler codegen: resolve → is_authenticated → derive_state → authorize → dispatch with identity
7. WS on-upgrade: resolve + derive_state, store identity + enriched_sc + page_shared_state + hostname + auth_timestamp on connection state (reject on resolve Error only)
8. WS handler codegen: enforce page-level auth on page-init frames (Required + is_authenticated, then authorize)
9. WS handler codegen: periodic re-resolve on message (30 min interval)
10. WS handler: send auth-failure / auth-redirect frames on policy failure
11. Error reporting: clear messages for missing auth exports, resolve Error → 500 with generic message

## Design Principles

- **Rally is generic.** It calls hooks, threads types, and acts on booleans. It never imports app domain types or makes domain decisions.
- **No auth module means no auth gate.** If a mount has no auth.gleam, Rally generates handlers without auth.
- **Convention over configuration.** File presence and export signatures are the configuration. No TOML knobs for auth.
- **App owns the identity.** The type, what it contains, how it's resolved, what "authenticated" means: all app decisions.
- **Authorization is page-local.** Each page knows its own access rules. No centralized route-to-role mapping to maintain.
- **One identity flow.** `resolve` is the single source of identity. `derive_state` consumes it. Save dispatch threads it. No parallel lookups, no inconsistent state.
- **Auth covers all surfaces.** SSR page loads, WebSocket saves, HTTP saves, and WebSocket page navigation all run through the same auth/authorize flow.
- **Fail loud on infrastructure errors.** Missing sessions are normal (anonymous). Broken auth checks are 500s.
- **Optional means skip is_authenticated, not skip authorize.** If a page exports authorize, it's enforced regardless of auth policy.
