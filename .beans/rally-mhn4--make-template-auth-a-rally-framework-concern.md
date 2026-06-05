---
# rally-mhn4
title: Make template auth a Rally framework concern
status: todo
type: epic
priority: normal
tags:
    - auth
    - template
created_at: 2026-06-05T04:08:18Z
updated_at: 2026-06-05T04:08:18Z
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
