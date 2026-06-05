---
# rally-i7ir
title: Generate SSR hydration adapter
status: completed
type: task
priority: high
tags:
    - codegen
    - ssr
created_at: 2026-06-04T23:18:18Z
updated_at: 2026-06-05T01:15:56Z
parent: rally-oymv
---

Scoreboard hand-authored server-side Rally hydration payload plumbing. Generate the SSR adapter that wraps page load wire results, Rally transport errors, generated protocol result envelopes, and base64 hydration payloads.

Problem:
- The app manually chooses route-specific boot load calls.
- The app manually maps page load results into page messages.
- The app manually encodes per-page hydration payloads.
- The app manually wraps page results into Rally/Libero wire result values.

Scope:
- Generate the route-to-page-load adapter for SSR boot.
- Generate per-page load-result-to-message glue where the page contract or convention makes the completion message unambiguous.
- Generate hydration payload encoding for Rally-managed page state.
- Keep app-owned shell rendering, auth/session identity, redirects, document metadata, and product-specific SSR decisions in authored app code.
- Make any remaining result-to-message declaration explicit if convention is not enough.

Non-goals:
- Do not generate public/admin shell HTML or app layout decisions.
- Do not generate page domain queries or page `load` functions.
- Do not generate app-specific redirect/auth policy.

Acceptance:
- Scoreboard `app_ssr` no longer contains repetitive Rally-owned hydration payload or load-result wrapping code.
- Generated SSR adapter lives under `src/generated/rally/**`.
- Targeted snapshot or generator tests cover generated SSR load, hydration, success result, and error result paths.
- Scoreboard SSR routes still build and render with the same page state.

Progress notes:
- Added generated `src/generated/rally/server_ssr.gleam` for hydration payload encoding and `LoadError` to transport error mapping.
- Scoreboard `app_ssr` no longer imports `generated/rally/result`, calls `server_protocol`, or performs base64 hydration encoding directly.
- Route-to-page load selection and page message application remain in app code. The boundary decision is now explicit: Rally should consume Proute page identity and page-owned load adapters, not infer route aliases or generate route/page shape.
