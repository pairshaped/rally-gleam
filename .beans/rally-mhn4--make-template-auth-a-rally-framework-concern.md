---
# rally-mhn4
title: Make template auth a Rally framework concern
status: in-progress
type: epic
priority: normal
tags:
    - auth
    - template
created_at: 2026-06-05T04:08:18Z
updated_at: 2026-06-05T21:43:49Z
---

Rally should grow an opinionated template-auth surface for our own apps first: emailed login codes, session cookies, protected-route redirects, boot identity, websocket auth context, and eventually Google SSO. This is not Auth0-lite. The goal is boring reusable plumbing for our personal project template, with app callbacks for product policy.

Current direction:

• Rally owns generic auth runtime mechanics: session cookie crypto, login-code generation/expiry plumbing, provider callback routing, redirect helpers, and boot/session extraction.
• Rally-generated glue can wire standard auth routes, protected SSR dispatch, websocket init auth context, browser boot identity, and sign-out/login flows.
• Apps still own user lookup/upsert, role/admin policy, email delivery, OAuth credentials, and product-specific redirects when they differ from the default.
• Email login code comes first. Google SSO comes after the shared session/user pipeline is stable.

First likely slice:

Move email login/session plumbing into Rally auth runtime while Scoreboard keeps user lookup and admin policy.

Acceptance criteria:

[ ] Scoreboard no longer owns generic session cookie crypto or login-code handler plumbing.
[ ] Rally exposes a small auth config/callback API for user lookup/upsert, email delivery, and role checks.
[ ] Existing sign-in, sign-out, admin redirect, SSR boot identity, websocket admin authorization, and browser smoke still pass.
[ ] Google SSO is planned as a second provider over the same session/user context pipeline, not as the core auth model.
[ ] The implementation stays opinionated for our template use and avoids over-generalized auth-product abstractions.

Risks:

The main risk is over-generalizing. If this starts becoming a generic auth platform, stop and narrow it back to the Scoreboard/template use case.

Starting implementation pass: inspect ADRs and current Scoreboard auth/session root modules before moving generic template-auth mechanics into Rally-owned generated/runtime code.

- Progress slice implemented: Rally runtime session now owns encrypted auth-session cookie encoding/decoding, auth cookie lookup, and auth cookie attributes through `rally/runtime/session` plus `rally_runtime_session_ffi`.
- Progress slice implemented: Scoreboard deleted `src/app_session.gleam` and `src/app_session_crypto_ffi.erl`; server context, SSR, document rendering, websocket admin auth, and sign-in issuing now use `rally/runtime/session.AuthSession`.
- Guarded: Scoreboard boundary guard rejects app-local session codec files, app-auth session-cookie lookup, app-auth-http cookie attribute builders, and app-local session crypto references.
- Still remaining in this epic: move generic sign-in/sign-out route handler plumbing and redirect helpers out of `app_auth_http.gleam`; keep Scoreboard user lookup, demo code verification policy, and admin policy app-owned.
- Validated: Rally `gleam test` passed (444 tests; existing generator-format warnings still printed).
- Validated: Scoreboard `gleam build --target erlang`, `gleam build --target javascript`, `TEMP=./tmp gleam test --target erlang`, `node test/ws_result_smoke.mjs`, and `node test/boundary_guard_test.mjs` passed.
- Validated: `npm run test:browser` failed once with transient startup `ERR_CONNECTION_REFUSED` at `/games`, then passed on immediate rerun through sign-in, admin save ack, and peer broadcast.

- Progress slice implemented: Rally runtime auth_http now owns generic sign-in form parsing, standard sign-in and invalid-code redirects, sign-out cookie expiry, safe local return path handling, and user-session cookie issuing.
- Progress slice implemented: Scoreboard app_auth_http now keeps product policy only: admin return-path narrowing, demo-code verification, user lookup, and admin role checks.
- Guarded: Scoreboard boundary guard rejects app_auth_http-local form parsing and standard auth response construction so generic auth HTTP mechanics stay in Rally.
- Style cleanup: the one-line issue_session wrapper was removed instead of preserving an unearned helper boundary. Gleam format keeps @target above function docs in the touched auth file, so that layout is formatter-owned here.
- Still remaining in this epic: protected SSR route wiring, boot identity, websocket auth context, and generated auth route glue remain app-root owned and should move through the same Rally-owned template surface.
- Validated: Rally `gleam test` passed (449 tests; existing generator-format warnings still printed).
- Validated: Scoreboard `gleam build --target erlang`, `gleam build --target javascript`, `node test/boundary_guard_test.mjs`, `TEMP=./tmp gleam test --target erlang`, `node test/ws_result_smoke.mjs`, and `npm run test:browser` passed.

- Progress slice implemented: Rally runtime env/session now own auth-session secret lookup, .env fallback, base64 validation, 32-byte key validation, error messaging, and missing-key development fallback.
- Progress slice implemented: Scoreboard app_config is now port-only; scoreboard_unified asks rally/runtime/session for AuthSession configuration and no longer owns secret decoding or random key generation.
- Guarded: Scoreboard boundary guard rejects app-local auth secret parsing and session-key construction in app_config.gleam and scoreboard_unified.gleam.
- Still remaining in this epic: generated auth route glue, protected SSR dispatch, boot identity extraction, websocket auth context, and app callback/config shape for user lookup and role checks.
- Validated: Rally `gleam test` passed (453 tests; existing generator-format warnings still printed).
- Validated: Scoreboard `gleam build --target erlang`, `gleam build --target javascript`, `node test/boundary_guard_test.mjs`, `TEMP=./tmp gleam test --target erlang`, `node test/ws_result_smoke.mjs`, and `npm run test:browser` passed.

- Progress slice implemented: Rally runtime auth_http now exposes RequestAuth callbacks for session-backed user loading and access policy, plus authenticated_user, authorized_user, protected-route redirect, and standard sign-in/sign-out route dispatch helpers.
- Progress slice implemented: Scoreboard app_auth_http now supplies app-owned auth callbacks and sign-in credential handling only; root server auth path dispatch, admin protected redirect, websocket admin access check, SSR boot user extraction, and document boot user extraction consume Rally auth_http helpers.
- Guarded: Scoreboard boundary guard rejects app-local auth cookie decoding in app_auth_http and auth method/path dispatch or manual sign-in redirects in scoreboard_unified.
- Still remaining in this epic: generated auth route glue can shrink the handwritten route closures further, and websocket auth context is still a Bool rather than generated/request-scoped identity context.
- Validated: Rally `gleam test` passed (456 tests; existing generator-format warnings still printed).
- Validated: Scoreboard `gleam build --target erlang`, `gleam build --target javascript`, `node test/boundary_guard_test.mjs`, `TEMP=./tmp gleam test --target erlang`, `node test/ws_result_smoke.mjs`, and `npm run test:browser` passed.

- Progress slice implemented: Scoreboard app_ssr now carries resolved shell identity and admin-access state on SsrApp, and app_document builds boot attrs from that result instead of resolving the request user a second time.
- Validated after boot cleanup: Scoreboard `gleam build --target erlang`, `gleam build --target javascript`, `node test/boundary_guard_test.mjs`, `TEMP=./tmp gleam test --target erlang`, `node test/ws_result_smoke.mjs`, and `npm run test:browser` passed.

- Progress slice implemented: Scoreboard websocket state now keeps the resolved admin user option instead of reducing request auth to an admin_authorized Bool at the app boundary. The generated server_ws Bool predicate remains as an adapter to the current generated contract.
- Guarded: Scoreboard boundary guard rejects app websocket state or init signatures that collapse admin auth back to a Bool.
- Still remaining in this epic: generated auth route glue can shrink handwritten route closures further, and generated websocket glue can eventually carry typed auth context directly instead of asking app_ws for a Bool adapter.
- Validated: Scoreboard `gleam build --target erlang`, `gleam build --target javascript`, `node test/boundary_guard_test.mjs`, `TEMP=./tmp gleam test --target erlang`, `node test/ws_result_smoke.mjs`, and `npm run test:browser` passed.
