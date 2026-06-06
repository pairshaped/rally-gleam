# Compose Proute Marmot And Libero

## Status

Accepted

## Decision

Rally is the framework coordinator. It composes Proute, Marmot, and Libero
rather than reimplementing their jobs.

Proute owns file routing and page glue. It discovers routes, generates route
types, route params, query params, page enums, page constructors, page update
dispatch, and page render dispatch. Proute-generated files live under
`src/generated/proute/**`.

Marmot owns migrations and SQL code generation. Rally commands that touch
migrations delegate to Marmot. Rally does not contain a migration runner.
Marmot-generated files live under `src/generated/sql/**`.

Libero owns wire codec generation. Rally passes page-local load/save and
broadcast type seeds to Libero. Libero walks the reachable type graph, writes
ETF codec modules, decoder registration, atom and wire modules, and contract
metadata. Libero-generated files live under `src/generated/libero/**`.

Rally owns the framework glue that composes those outputs: app-facing transport
helpers, request/result correlation, hydration, SSR composition, browser boot,
server dispatch, WebSocket connection state, topic sync, generated protocol
wrappers, and standard app runtime conventions. Rally-generated files live under
`src/generated/rally/**`.

## CLI Pipeline

`rally gen` runs configured Marmot codegen, runs Proute when `proute.toml`
exists, discovers Rally page contracts, drives Libero generation for
Rally-managed wire types, and writes Rally generated files.

`rally regen` deletes `src/generated` before running `gen`.

`rally build` runs `gen`, then builds Erlang and JavaScript targets.

`rally migrate` delegates to `marmot migrate`.

`rally reset` delegates to `marmot reset`, including seeds.

`rally server` stops any process listening on `PORT` or 8080, then runs
`gleam run` in the foreground.

Rally checks delegated dependencies before shelling out. `[tools.marmot]`
requires a direct `marmot` dependency. Rally wire generation requires `libero`.
Proute is a Rally dependency; apps configure routes with `proute.toml` but do
not need to list `proute` directly.

## Consequences

Rally does not generate Proute-owned route files, Marmot-owned SQL modules, or
Libero-owned codec artifacts by hand.

Generated Rally glue consumes Proute output instead of rediscovering routes.
Generated Rally protocol glue calls Libero-generated codec helpers instead of
copying ETF runtime code.
