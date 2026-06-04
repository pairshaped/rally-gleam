---
# rally-df3o
title: Generate browser app boot wrapper
status: todo
type: task
priority: normal
tags:
    - codegen
    - browser
created_at: 2026-06-04T23:18:39Z
updated_at: 2026-06-04T23:18:39Z
parent: rally-oymv
---

Scoreboard public/admin browser modules still hand-author Rally browser boot plumbing. Generate or centralize the Lustre browser app wrapper so authored app modules only provide app-owned callbacks and shell/shared-state behavior.

Problem:
- Browser modules manually start Lustre apps.
- They manually parse routes and build startup effects.
- They manually apply hydration fallback and server frames.
- They manually wrap browser navigation into route load effects.

Scope:
- Generate a browser app adapter for each Rally app target, or generate enough helper surface that public/admin wrappers become app-owned shell configuration only.
- Keep app-owned shared state, shell rendering, auth UI, dark-mode state, and page view/update behavior in authored code.
- Reuse generated boot/hydration modules instead of duplicating route-load and broadcast-apply code.
- Preserve target-specific behavior for public and admin applications.

Non-goals:
- Do not generate page view functions.
- Do not generate app shell layout.
- Do not force one shared-state type across targets.

Acceptance:
- Scoreboard public/admin browser app modules no longer hand-write generic Rally startup, hydration fallback, frame apply, and navigation effect plumbing.
- Generated code remains under `src/generated/rally/**`.
- Existing public/admin browser behavior still works after regeneration.
- Tests or snapshots cover the generated browser boot shape.
