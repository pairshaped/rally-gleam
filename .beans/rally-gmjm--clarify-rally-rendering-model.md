---
# rally-gmjm
title: Clarify Rally rendering model
status: completed
type: task
priority: normal
created_at: 2026-06-06T18:51:21Z
updated_at: 2026-06-06T19:02:20Z
---

Update Rally docs so the opening description says Rally server-renders initial HTML, hydrates in the browser, and then runs client-side Lustre, avoiding server-components wording.

## Summary of Changes

Updated the README and llms.txt opening description to say Rally server-renders the initial HTML, hydrates in the browser, and then continues as a client-side Lustre app. This avoids implying Rally is a server-components model.

## Validation

- git diff --check
- rg confirmed the old wording is gone from README.md and llms.txt.

## Additional Note

The Writing a page section also needed to explain the generated load roundtrip. The page defines `ServerMsg`, `LoadResult`, `Loaded`, and `load`, but generated Rally code initiates the browser/server load and dispatches the result.

## Summary of Additional Changes

Clarified the Writing a page section: app pages define the load contract, while generated Rally browser/server code initiates the WebSocket request, calls the Erlang `load(db)`, and dispatches `Loaded(...)` back through `update`.

## Validation

- git diff --check

## Additional Note

Clarified save wording in the README. `handle` remains the Erlang save hook, while browser page code calls generated `generated/rally/server.save_*` effects.

## Summary of Additional Changes

Split the save documentation into the server-side `handle` hook and the browser-side generated `generated/rally/server.save_*` effect call.

## Validation

- git diff --check
