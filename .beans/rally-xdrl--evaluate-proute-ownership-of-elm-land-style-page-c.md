---
# rally-xdrl
title: Evaluate Proute ownership of Elm Land-style page construction
status: todo
type: feature
priority: normal
created_at: 2026-06-06T01:45:35Z
updated_at: 2026-06-06T01:45:35Z
---

Rally currently consumes generated Proute page and route modules, but the Elm Land-inspired part of this design is really page construction: route identity, route params, query params, page model replacement, and hook signatures for init/update/topics/subscriptions. Evaluate moving that API responsibility into Proute so Rally owns browser lifecycle, hydration, transport, and load/save wiring while Proute owns route-to-page construction shape.
