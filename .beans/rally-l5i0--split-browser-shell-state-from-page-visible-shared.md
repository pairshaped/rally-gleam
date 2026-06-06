---
# rally-l5i0
title: Split browser shell state from page-visible shared state
status: completed
type: feature
priority: normal
created_at: 2026-06-06T01:55:41Z
updated_at: 2026-06-06T02:02:09Z
---

Rally/Scoreboard currently use descriptive ClientSharedState because the source tree contains both client and server code, but the type now mixes browser shell/runtime data with page-visible shared app state. Evaluate an Elm Land-style split that keeps naming clear in a unified client/server source tree: browser or mount shell state for active path, dark mode, toast, and boot mechanics; a page-visible shared model for app facts pages may opt into; and server context/session names kept distinct. Coordinate with the Proute page-construction bean so pages receive shared app state through generated page construction where appropriate.

## Summary of Changes

- Split the generated browser mount model/config into `shell_state` and `page_shared_state` slots.
- Changed generated page-context derivation to read from page-visible shared state, while route and dark-mode lifecycle updates mutate shell state.
- Regenerated the Scoreboard browser app glue against the new API.
- Replaced public/admin `ClientSharedState` modules with separate `ClientShellState` and `ClientPageSharedState` modules.
- Kept auth/admin-access in page-visible shared state and active path/dark mode/toast-style fields in shell state.
- Updated ADR 0012 to describe the split and keep the Elm Land-inspired direct page-shared construction as the next Proute-aligned direction.
