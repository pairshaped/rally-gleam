---
# rally-tlwx
title: Rewrite Rally docs around unified Scoreboard path
status: completed
type: task
priority: normal
created_at: 2026-06-06T05:24:01Z
updated_at: 2026-06-06T05:33:32Z
parent: rally-536z
---

Update README, llms.txt, guide pages, and reference pages so they describe Rally Scoreboard style unified source generation rather than generated-client packages, server_* RPC, stateful server pages, or .generated_clients.

Acceptance:
- User-facing docs point Proute, Rally, and Libero readers to the Rally Scoreboard example.
- No user-facing docs advertise legacy-build, legacy-gen, [[tools.rally.clients]], .generated_clients, or server_* RPC as the main path.
- ADR wording stays current/intended design only.

## Summary of Changes

Updated README, llms.txt, guides, reference docs, design docs, and scaffold README text around the unified Rally Scoreboard path. Rewrote the pages guide to use `initial_model`, page shared state, route/query params, page-local load/save, and typed broadcasts. Removed stale generated-client, legacy CLI, RealWorld, ClientContext/init_loaded, deleted-module, and old scaffold path references from user-facing docs.

Validation: stale-term `rg` scans returned no matches; `gleam format && gleam test` passes with 189 tests.
