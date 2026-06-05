---
# rally-5ztp
title: Add provider auth callbacks for email and Google SSO
status: todo
type: feature
priority: deferred
tags:
    - auth
    - template
created_at: 2026-06-05T22:34:09Z
updated_at: 2026-06-05T22:34:09Z
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
