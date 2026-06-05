---
# rally-u847
title: Hide Libero from app install surface
status: scrapped
type: task
priority: normal
tags:
    - docs
    - codegen
created_at: 2026-05-14T00:58:43Z
updated_at: 2026-06-04T21:05:36Z
---

Generated Rally apps currently import libero modules directly, so users must add libero as an app dependency. Make generated code import Rally-owned facades instead so onboarding can be just `gleam add rally`.



Decision: scrapped after clarifying the Libero boundary. Libero is a public lower-level codec/runtime library, and generated code that imports `libero/*` should list Libero as a direct dependency in that package. Rally should reduce unnecessary Libero coupling, but should not hide a real runtime import behind transitive dependencies.
