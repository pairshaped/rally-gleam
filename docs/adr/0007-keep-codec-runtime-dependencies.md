# Keep Codec Runtime Dependencies

## Status

Accepted

## Decision

Libero and Rally remain runtime dependencies for the code they own.

Libero owns ETF wire encoding, decoding, decoder registration, atom
registration, wire metadata, and contract metadata. Libero-generated modules
live under `src/generated/libero/**`.

Rally owns framework glue around those codecs: request ids, pending callback
registration, WebSocket transport, result envelopes, broadcast frame dispatch,
hydration decoding, browser boot, SSR composition, and server dispatch.
Rally-generated modules live under `src/generated/rally/**`.

Rally-generated code may consume Libero runtime modules directly. Any package
with generated imports of `libero/*` lists Libero as a runtime dependency, like
a package with Marmot-generated SQL access code lists the database runtime it
uses.

The app depends on these generated/runtime surfaces:

- `rally/runtime/load` for the standard page load error type.
- `generated/rally/result` for transport result envelopes such as
  `ApiLoadError` and `ApiSaveError`.
- `generated/libero/etf` as the neutral ETF entrypoint used by Rally protocol
  glue.
- `generated/libero/rpc_decoders` and `generated/libero/rpc_decoders_ffi.mjs`
  for browser constructor and decoder registration.
- `generated/libero/generated@rpc_wire.erl` for typed server-side wire encoders
  and decoders.
- `generated/rally/client_transport` for WebSocket connection, request ids, and
  result callback dispatch.
- `generated/rally/client_protocol` and `generated/rally/server_protocol` for
  request, result, and broadcast frame envelopes.
- `generated/rally/browser`, hydration, browser app, and mount helpers for
  browser-specific framework plumbing.

Rally should not author ETF codec modules, atom modules, wire modules, decoder
registration modules, or Libero contract JSON by hand. When Rally drives Libero
generation, those outputs remain Libero-owned generated artifacts.

## Consequences

Rally can provide a small generated app-facing API while keeping codec runtime
behavior in Libero.

Applications list the libraries required by generated code instead of hiding
runtime dependency edges inside copied generated source.
