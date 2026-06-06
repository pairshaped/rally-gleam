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
updated_at: 2026-06-06T03:18:56Z
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
