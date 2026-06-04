---
# rally-vfiu
title: Move ETF RPC dispatch generation into Rally
status: completed
type: task
priority: high
tags:
    - codegen
    - architecture
created_at: 2026-06-04T20:30:29Z
updated_at: 2026-06-04T20:51:58Z
---

Rally still calls Libero's legacy dispatch generators for ETF RPC handler routing. Move that dispatch generation into Rally so Libero can stay focused on type discovery, codec and contract artifact generation, and runtime wire primitives.

Acceptance criteria:

- Rally no longer calls `libero.generate_dispatch` or `libero.generate_dispatch_with_extra_params`.
- Generated `rpc_dispatch.gleam` is identified as Rally-generated code.
- The generated dispatch preserves current ETF handler routing behavior, including auth identity extra params, context mutation, malformed request handling, unknown function handling, and per-handler wire encoding.
- Rally may still consume Libero scanner endpoint metadata and wire encoder/runtime helpers.
- Existing Rally handler, WS, and HTTP tests cover the generated shape.

Non-goals:

- Do not remove Libero scanner, walker, field type, codec generation, or runtime wire use in this task.
- Do not change JSON client-context behavior here.

Additional test preservation requirement:

- Do not lose Libero's existing cross-runtime codec coverage. Since Libero owns encode/decode behavior, Libero should retain full encode/decode tests for ETF and JSON in both JavaScript and Erlang, including primitives, custom types, nested custom types, collections, options/results, and cross-module custom types. Rally should keep framework integration tests that prove generated Rally code consumes Libero correctly.
