# Internals

This page is for contributors working on Rally itself. Application code should treat `rally/internal/...` as private. These modules have no stability guarantees and can change between releases.

## Pipeline

Rally's codegen runs as a single pass through this pipeline:

```text
gleam.toml config
  -> scanner
  -> parser
  -> Libero handler scan and type walk
  -> generators
  -> tree shaker
  -> dependency resolver
  -> file output
```

The scanner reads the filesystem, the parser extracts page contracts from the AST, Libero walks handler types, and the generators produce Gleam/Erlang/JS source strings. The tree shaker strips server-only code from client builds, and the dependency resolver follows imports to copy shared modules into the client package.

## Reading order

If you are new to the codebase, read these files in order:

1. `src/rally/internal/types.gleam`: shared codegen vocabulary (route types, page contracts, config)
2. `src/rally/internal/scanner.gleam`: filesystem walk that discovers page modules
3. `src/rally/internal/parser.gleam`: Glance AST inspection to extract each page's contract
4. `src/rally.gleam`: CLI entry point and pipeline orchestration
5. `src/rally/internal/generator.gleam`: route type, `parse_route`, and page dispatch generation
6. `src/rally/internal/generator/ws_handler.gleam`: WebSocket runtime generation
7. `src/rally/internal/tree_shaker.gleam`: client/server source splitting

The generator files (`internal/generator/*.gleam`) build Gleam/Erlang/JS source as strings. They are harder to read than normal code. Start with `internal/generator.gleam` (route type and parse function) before moving to `ws_handler` or `ssr_handler`.

## Boundary with Libero

Rally and Libero split responsibility along a clear line:

**Rally owns:** pages, routing, SSR, WebSocket integration, client package generation, and runtime glue.

**Libero owns:** handler discovery, type walking, wire identity, protocol encoding, response decoding, and RPC dispatch code.

Rally calls into Libero after the scanner and parser have extracted the page structure. From that point, Libero owns everything related to wire protocol and RPC dispatch. If you are working on how messages get encoded, decoded, or dispatched, you are working in Libero's domain.

## Project layout

```
src/
  rally.gleam                    # CLI entry point
  rally/internal/
    scanner.gleam                # Filesystem walk -> List(ScannedRoute)
    parser.gleam                 # Glance AST -> PageContract
    types.gleam                  # Shared pipeline types
    tree_shaker.gleam            # Strips server code from page source
    dependency_resolver.gleam    # Follows imports to copy shared modules
    format.gleam                 # Runs gleam format on generated code
    generator.gleam              # Route type, parse_route, page dispatch
    generator/
      client.gleam               # Client package: gleam.toml, app.gleam, transport
      codec.gleam                # Client codegen: types, decoders, effect shim
      ssr_handler.gleam          # SSR handler codegen
      ws_handler.gleam           # WebSocket handler codegen
      http_handler.gleam         # HTTP RPC handler codegen
      json_rpc_dispatch.gleam    # JSON-specific RPC dispatch codegen
  rally/runtime/
    effect.gleam                 # rpc, broadcast, navigate
    db.gleam                     # SQLite helpers
    system.gleam                 # System DB, job queue
    session.gleam                # Session cookies
    ...
```

## Testing

Tests live under `test/rally/` (scanner, parser, generator, codec, auth tests) and `test/rally/runtime/` (wire, session, broadcast, jobs tests). Fixture apps live under `fixtures/`. Run with `gleam test`. Snapshot tests use Birdie.
