---
# rally-sb6j
title: Centralize Rally page load error type
status: todo
type: task
priority: normal
tags:
    - generator
    - load-rpc
created_at: 2026-06-06T03:41:22Z
updated_at: 2026-06-06T03:41:33Z
---

Repeated exact page-local load error types like `pub type LoadError { LoadError(message: String) }` should be centralized instead of copied into every Rally page.

Current blocker:

- Generated Rally browser/SSR/WS glue hardcodes page-local constructors such as `public_games_wire.LoadError(message:)`.
- Gleam type aliases do not re-export constructors, so changing pages to `pub type LoadError = load_error.LoadError` breaks generated callers.

Goal:

- Pick a single root-level load error type for Rally page load failures, likely app-owned `load_error.LoadError` or a generated Rally result type if that proves cleaner.
- Update Rally load RPC generation so browser app, SSR, WS, and direct load mapping construct and pattern-match the shared type instead of `page.LoadError`.
- Update the Scoreboard example pages to use the shared type and remove duplicated page-local `LoadError` declarations.
- Keep domain-specific load errors in server-component pages alone; only consolidate the repeated message-shaped Rally load error.

Acceptance criteria:

[ ] Repeated `LoadError(message: String)` page declarations are removed from Rally Scoreboard pages.
[ ] Regenerated Rally glue compiles without page-local `LoadError` constructors.
[ ] Erlang and JavaScript Scoreboard tests pass.
[ ] Rally generator snapshots document the new shared load-error boundary.

Decision update:

This should be a Rally-owned type, not an app-owned root type. The repeated shape is not product data; it is the standard Rally page-load failure boundary. Prefer a runtime type such as `rally/runtime/load.LoadError` (or similarly named Rally runtime module) that authored pages can import directly, while generated Rally browser/SSR/WS glue also constructs and pattern-matches it. Keep `generated/rally/result.ApiLoadError` as the transport envelope if needed, but page code should see the Rally runtime load error, not a generated transport-specific type.
