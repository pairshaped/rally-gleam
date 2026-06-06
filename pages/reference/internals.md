# Internals

This page is for contributors working on Rally itself. Application code should treat `rally/internal/...` as private. These modules have no stability guarantees and can change between releases.

## Pipeline

Rally's codegen runs as a single pass through this pipeline:

```text
gleam.toml config
  -> Marmot when configured
  -> Proute when proute.toml exists
  -> page contract discovery
  -> Libero type walk and codec generation
  -> Rally generators
  -> file output
```

Rally reads page contracts from authored page modules, Proute owns route params and page dispatch, Libero walks reachable handler types, and Rally generators produce Gleam/Erlang/JS source strings for SSR, hydration, browser boot, WebSocket transport, topics, and load/save dispatch.

## Reading order

If you are new to the codebase, read these files in order:

1. `src/rally.gleam`: CLI entry point and pipeline orchestration
2. `src/rally/internal/init.gleam`: starter app scaffold generation
3. `src/rally/internal/generator/load_rpc.gleam`: Rally Scoreboard Example load/save, SSR, browser, hydration, WebSocket, topic, and protocol generation
4. `src/rally/internal/format.gleam`: formatting generated source

The generator files build Gleam/Erlang/JS source as strings. They are harder to read than normal code. Start with the Scoreboard example output, then read `load_rpc.gleam` with that output nearby.

## Boundary with Libero

Rally and Libero split responsibility along a clear line:

**Rally owns:** pages, routing composition, SSR, WebSocket integration, browser lifecycle, hydration, topics, and runtime glue.

**Libero owns:** handler discovery, type walking, wire identity, protocol encoding, response decoding, and request/result dispatch code.

Rally calls into Libero after it has extracted the page load/save contracts. From that point, Libero owns everything related to wire protocol and typed request/result encoding. If you are working on how messages get encoded or decoded, you are working in Libero's domain.

## Project layout

```
src/
  rally.gleam                    # CLI entry point
  rally/internal/
    init.gleam                   # Starter app scaffold generation
    format.gleam                 # Runs gleam format on generated code
    generator/
      load_rpc.gleam             # Rally Scoreboard Example generation
  rally/runtime/
    effect.gleam                 # navigation and broadcast effects
    db.gleam                     # SQLite helpers
    system.gleam                 # System DB, job queue
    session.gleam                # Session cookies
    ...
```

## Testing

Tests live under `test/rally/` for CLI, scaffold, generator, smoke, auth, and runtime contracts. Fixture apps live under `fixtures/`. Run with `gleam test`. Snapshot tests use Birdie.
