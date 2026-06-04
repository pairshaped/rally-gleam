---
# rally-j9vs
title: Handle repeated system DB starts
status: completed
type: task
priority: deferred
tags:
    - runtime
created_at: 2026-05-14T22:58:47Z
updated_at: 2026-06-04T22:57:41Z
---

system.open_and_store opens a fresh SQLite connection and writes global state on every start. That preserves existing behavior, but supervised job-runner restarts make repeated starts more likely. Replace or close old global state deliberately in a future pass.



## Completion notes

Repeated system starts now deliberately replace Rally’s stored system DB connection and close the previous connection after the new one is installed. The old `global_value` call was removed from this path, and Rally no longer declares `global_value` as a direct dependency.

Validation:

- `gleam build`
- `gleam test --target erlang` (424 passed)
