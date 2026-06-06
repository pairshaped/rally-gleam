---
# rally-l5i0
title: Split browser shell state from page-visible shared state
status: todo
type: feature
priority: normal
created_at: 2026-06-06T01:55:41Z
updated_at: 2026-06-06T01:55:41Z
---

Rally/Scoreboard currently use descriptive ClientSharedState because the source tree contains both client and server code, but the type now mixes browser shell/runtime data with page-visible shared app state. Evaluate an Elm Land-style split that keeps naming clear in a unified client/server source tree: browser or mount shell state for active path, dark mode, toast, and boot mechanics; a page-visible shared model for app facts pages may opt into; and server context/session names kept distinct. Coordinate with the Proute page-construction bean so pages receive shared app state through generated page construction where appropriate.
