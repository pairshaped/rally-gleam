---
# rally-7wan
title: Generate SSR page load adapters from page load_wire
status: completed
type: task
priority: high
tags:
    - boundary-cleanup
created_at: 2026-06-05T03:59:14Z
updated_at: 2026-06-05T03:59:14Z
parent: rally-kobq
---

Completed as a slice of rally-d4tc.

SSR public page loads no longer require app_ssr callback fields for each public page. Rally server_ssr generation now uses the configured load RPC context to call page-owned load_wire functions directly for client-importable loads whose route args can be safely extracted as String or Int. Unsupported or app-policy-sensitive loads continue to use app callbacks.

Scoreboard app_ssr now provides only load_context for public SSR loads. Route-to-message selection remains app-owned for now. Public `Home` is a real `home_.gleam` page; any delegation to the games load belongs in that page or in a page-owned adapter, not in a Rally alias convention.

Validated with:

• Rally gleam build
• Rally gleam test --target erlang -- --module rally/codegen_load_rpc_snapshot_test
• Scoreboard clean regeneration after deleting src/generated/rally and src/generated/libero
• Scoreboard gleam build --target erlang
• Scoreboard gleam build --target javascript
• Scoreboard gleam test --target erlang
• Scoreboard node test/boundary_guard_test.mjs
• Scoreboard node test/ws_result_smoke.mjs
