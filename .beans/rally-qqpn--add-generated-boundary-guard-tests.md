---
# rally-qqpn
title: Add generated-boundary guard tests
status: todo
type: task
priority: normal
tags:
    - tests
    - architecture
created_at: 2026-06-04T23:18:50Z
updated_at: 2026-06-04T23:18:50Z
parent: rally-oymv
blocked_by:
    - rally-tbnf
    - rally-i7ir
    - rally-l4zl
    - rally-df3o
---

Add tests or static guard checks that keep Rally-owned generated internals out of authored app and page modules once the extraction work lands.

Problem:
- Scoreboard currently imports generated transport/result/protocol internals from authored app/page modules.
- Without guardrails, future changes can drift back into hand-authored Rally plumbing even after generators learn to emit the right adapters.

Scope:
- Add focused guard checks in Rally tests, Scoreboard tests, or both, depending on where the project already validates generated app shape.
- Check authored page modules do not import `generated/rally/client_transport` or `generated/rally/result` directly.
- Check authored app websocket modules do not import `generated/rally/server_protocol` or call Mist binary-frame send APIs for Rally request/result dispatch.
- Check authored SSR modules do not hand-author hydration payload/result wrapper functions that generated Rally adapters own.
- Keep generated modules free to import generated Rally internals and Libero runtime/codec modules.

Non-goals:
- Do not ban generated Rally imports globally.
- Do not ban app-owned broadcast modules or page-local wire modules.
- Do not make brittle line-number assertions against app files.

Acceptance:
- Boundary guard tests fail before the extraction work or with a small fixture that reproduces the old pattern.
- Boundary guard tests pass once the generated adapters are used.
- The checks encode the responsibility boundary, not incidental file names beyond stable generated namespaces.
