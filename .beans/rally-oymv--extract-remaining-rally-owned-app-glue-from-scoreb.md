---
# rally-oymv
title: Extract remaining Rally-owned app glue from Scoreboard
status: todo
type: epic
priority: high
tags:
    - codegen
    - architecture
created_at: 2026-06-04T23:17:49Z
updated_at: 2026-06-04T23:17:49Z
---

Scoreboard is now a useful reality check for the Rally boundary: generated code owns more protocol and boot glue than before, but authored app modules still contain framework plumbing that should be generated from Rally/Proute/Libero metadata.

Goal:
- Move Rally-owned websocket, SSR hydration, browser boot, and page RPC call plumbing out of hand-authored app/page modules.
- Keep app-owned behavior in the app: auth/session decisions, shell composition, domain load/handle/update/view logic, broadcast policy, and product-specific route decisions.
- Preserve the boundary from ADR 0009: Libero owns codec/contracts/artifacts, Proute owns route/page shape, Rally owns framework glue.

Reality check findings this epic tracks:
- Server websocket dispatch in the Scoreboard app manually decodes frames, correlates request IDs, encodes result frames, and calls Mist transport APIs.
- SSR boot/hydration in the Scoreboard app manually routes page load results into hydration payloads and page messages.
- Browser app modules hand-author Lustre startup/navigation/hydration frame plumbing.
- Page modules import generated transport/result internals directly instead of using a stable Rally page API.
- There are no guard tests yet that prevent authored app/page code from drifting back into generated internals.

Acceptance:
- Scoreboard authored app code no longer hand-writes Rally-owned transport/hydration/browser boot glue.
- Page modules use a stable Rally-facing API instead of generated transport internals.
- Generated Rally modules may consume Libero runtime/codec modules directly when appropriate.
- Regression guards enforce the intended import and responsibility boundaries.
