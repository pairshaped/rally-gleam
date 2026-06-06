---
# rally-5ztp
title: Add provider auth callbacks for email and Google SSO
status: in-progress
type: feature
priority: deferred
tags:
    - auth
    - template
created_at: 2026-06-05T22:34:09Z
updated_at: 2026-06-06T03:29:51Z
---

Rally now has the shared session/user context pipeline for the template apps. The next provider slice should build on that pipeline instead of changing the core model.

Scope:

- Add a production email-code delivery path with app-owned delivery callbacks and Rally-owned provider routing mechanics.
- Add Google SSO as a second provider that issues the same Rally auth session after app-owned user lookup/upsert.
- Keep user lookup/upsert, role policy, OAuth credentials, and mail-provider configuration app-owned.
- Do not turn this into a generic auth product; design against the Scoreboard/template app path first.

Acceptance criteria:

[ ] Email-code delivery uses Rally-owned provider routing and session issuing.
[ ] Google SSO signs in through the same Rally session/user context pipeline.
[ ] Apps provide explicit callbacks for user lookup/upsert and provider credentials.
[ ] Existing Scoreboard sign-in, sign-out, admin redirect, SSR boot identity, websocket admin authorization, and browser smoke still pass.



Convention boundary:

Provider auth should follow ADR 0012. Rally owns provider routing mechanics, callback invocation, session issuing, config/env parsing, and standard bootstrap integration. Apps own user lookup/upsert policy, role policy, provider credentials/secret values, email copy/provider choice, and any product-specific route narrowing.



## Progress

- Added Rally-owned email-code provider start routing: `POST /sign_in/code` parses the form, validates the local return path, invokes an app-owned delivery callback, and redirects back to sign-in with `sent=1` or `error=invalid`.
- Kept existing `POST /sign_in` as the code verification and Rally session issuing path.
- Documented `rally/runtime/auth_http` as the standard email-code HTTP route surface.

Validation: `gleam format && gleam test` passes with 467 tests.

Remaining: Google SSO callback flow and full provider callback shape for OAuth credentials/user upsert.

- Added Rally-owned Google OAuth route mechanics: GET /sign_in/google creates state and return_to cookies before redirecting to Google, and GET /sign_in/google/callback verifies state, calls the app-owned provider sign-in callback, issues the same Rally auth session, and clears temporary cookies.
- Kept Google code exchange, identity verification, credential loading, and user lookup/upsert app-owned.
- Documented rally/runtime/auth_http as the shared provider route surface for email-code and Google.

Remaining: wire the Google route surface through Scoreboard/template bootstrap and settle the full provider callback shape for app credentials/user upsert.

- Tightened Google route configuration to use an explicit GoogleCredentials callback and return 503 when the app has not configured Google.
- Wired Scoreboard to the shared Google route surface: the root auth handler delegates to Rally for Google route mechanics, app_auth_http owns credential lookup, and app_auth owns the provider callback boundary.
- Kept the Scoreboard UI email-code-only until a real Google code exchange and identity verification implementation exists; no fake Google sign-in path was added.
- Updated Scoreboard ADR 0012 and .env.example for provider credential ownership and the Rally-owned standard auth route mechanics.

Validation: Rally gleam format && gleam test passes with 471 tests. Scoreboard gleam format, TEMP=./tmp gleam test --target erlang, gleam test --target javascript, and node test/boundary_guard_test.mjs pass.

Remaining: implement the app-owned Google code exchange, identity verification, and user lookup/upsert callback for a real deployment path before exposing a Google button in the demo UI.
