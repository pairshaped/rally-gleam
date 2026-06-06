---
# rally-v91h
title: Implement real Google OAuth exchange for template auth
status: todo
type: task
priority: deferred
tags:
    - auth
    - template
created_at: 2026-06-06T03:32:35Z
updated_at: 2026-06-06T03:32:35Z
---

- Add an app-owned Google provider implementation for the Scoreboard/template path that exchanges the OAuth code for tokens, verifies the Google identity token, and looks up or upserts the local user.
- Keep Rally owning provider route mechanics, state cookies, callback invocation, and Rally session issuing.
- Keep client secret, provider HTTP calls, Google identity policy, user lookup/upsert, and allowed-domain policy app-owned unless Rally later grows a deliberately tested provider client.
- Do not expose a Google sign-in button in the example until this path is real and covered.

Acceptance criteria:

[ ] Scoreboard can sign in through Google using real configured credentials.
[ ] The callback validates state, exchanges code, verifies identity, and returns a local user id through Rally auth_http.GoogleCallback.
[ ] Tests cover missing credentials, provider failure, invalid identity, and successful local session issuing.
[ ] The sign-in page exposes Google only when configured.
