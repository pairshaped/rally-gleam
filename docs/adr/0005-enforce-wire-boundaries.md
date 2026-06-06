# Enforce Wire Boundaries

## Status

Accepted

## Decision

Wire-visible page protocols may reference only:

- types defined in the owning page module or page wire module
- types defined under `src/wire/**`
- app-wide broadcast event types defined in `src/broadcasts.gleam`
- primitives
- standard containers such as `List`, `Result`, `Option`, tuples, and records
  that contain approved wire-visible types

Wire-visible page protocols must not reference helper, service, query,
business, formatting, SQL row, or display types. This rule is transitive: a
type that contains an unapproved owned type is not wire-visible.

Helpers, services, query modules, business modules, formatting modules, and SQL
modules remain valid behavior dependencies. Page code can call them. Their owned
shapes cannot become the wire contract.

Proute owns page identity. Rally consumes Proute's page identity before
dispatching incoming wire messages, then decodes page-local payloads for that
page. Page-local type names stay page-local.

Boundary diagnostics should name the violated contract, the offending type or
import, the path that made it reachable, and the smallest likely fix.

## Consequences

The browser/server wire stays explicit and page-owned. Accidental helper or SQL
row types do not leak into generated codecs.

Two pages may define same-named local payload types without relying on global
type identity hashes for page dispatch.
