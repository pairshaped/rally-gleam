---
# rally-ad2i
title: Make Rally the official consumer path for Libero
status: todo
type: task
priority: high
tags:
    - codegen
    - architecture
created_at: 2026-06-04T19:11:16Z
updated_at: 2026-06-04T19:57:36Z
---

Rally should become the official way Libero is consumed. Libero remains the owner of ETF codecs, contracts, atom coverage, and generated Libero artifacts, but its public workflow should align with being driven by Rally rather than by direct app usage.

Acceptance criteria:
- Rally discovers or produces the wire-type manifest needed by Libero for Rally-managed app surfaces.
- Example apps no longer need to hand-maintain `tools.libero.type_seeds` for Rally-owned wire needs.
- Rally invokes or feeds Libero through a clear lower-level interface instead of requiring app authors to understand Libero internals.
- Boundary stays intact: Rally does not generate Libero-owned codec artifacts, and Libero does not own page routing, transport, hydration, request/result correlation, or app behavior.
- Document the intended relationship: Rally is the app-facing entrypoint; Libero is the typed wire-code generation engine Rally consumes.

Non-goals:
- Do not remove Libero legacy standalone scanning in this task unless it becomes trivial after the Rally path is complete.
- Do not merge Libero into Rally. The goal is an explicit consumer/engine relationship, not ownership collapse.

Related:
- `rally-u847` covers hiding Libero from the app install surface. This bean covers making Rally the official driver/consumer path so future Libero cleanup is easier.



Priority note:
- Promote this now because broad Rally tests are blocked by a Libero standalone dispatch-generator bug in the JSON protocol fixture (`ServerIncrementBy(amount:)` emitted after discarding `amount`). That is Libero-owned behavior leaking through Rally because Rally still asks Libero to generate dispatch.
- The point is not to patch that bug in Rally. The point is to make Rally the official driver/consumer of Libero and stop depending on Libero-owned app dispatch generation for Rally-managed surfaces.
- This should happen before more legacy Libero-dispatch bugs distract the Rally epic.
