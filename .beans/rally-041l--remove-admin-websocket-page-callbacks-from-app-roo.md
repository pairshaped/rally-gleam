---
# rally-041l
title: Remove admin websocket page callbacks from app root
status: todo
type: task
priority: high
tags:
    - boundary-cleanup
    - websocket
created_at: 2026-06-05T19:04:55Z
updated_at: 2026-06-05T19:23:53Z
parent: rally-kobq
---

## Problem

`rally-scoreboard-example/src/app_ws.gleam` still imports `admin/pages/games` and wires page-specific load/save callbacks into generated `server_ws`:

- `admin_games_load` calls `admin_games_page.load_wire`.
- `admin_games_save` calls `admin_games_page.handle`.
- `after_admin_games_save` and broadcast helpers depend on `admin_games_page.ServerMsg` and `GameUpdate`.

That means the app root still knows page-owned wire types and page functions for admin websocket RPCs. Public websocket loads are already generated from `load_context`, and SSR admin loads now are too.

## Intended direction

Centralize broadcast behavior instead of peppering it through root modules.

- `broadcasts.gleam` should own the app broadcast payload types, typed topic constructors, topic-to-runtime-name conversion, and targeted-event construction for domain events.
- Page modules should own topic interest/subscriptions and topic updates: pages declare which typed topics they care about from their current model, and page update hooks apply decoded broadcast events.
- Rally generators should own the repetitive websocket mechanics: decode request, authorize, call page load/save from configured context, encode result, sync subscriptions, turn typed topics into runtime `pg` groups, and broadcast after successful saves.
- Root modules such as `app_ws.gleam` and `app_api.gleam` should not import page modules, match page `ServerMsg` constructors, call page `load_wire`/`handle`, or convert generated SQL rows into broadcast payloads.

App-owned policy should remain explicit: authorization, product broadcast meaning, and which domain event is emitted after a save. The mapping should be declared once at the page/domain boundary and consumed by generated Rally glue.

## Acceptance criteria

- `src/app_ws.gleam` no longer imports `admin/pages/games`.
- App websocket code does not call page-owned `load_wire` or `handle` directly.
- App websocket code keeps authorization and broadcast meaning app-owned.
- Existing admin load/save, websocket result, broadcast-except-origin, and browser smoke behavior still pass.
- Scoreboard boundary guard catches page-specific websocket callback leaks in app root.

## Design Note

The remaining app root websocket code is mostly mechanical mapping. Broadcast mapping should still be user-defined, but it should be defined once at the page/domain boundary instead of repeated in `app_ws.gleam`.

Preferred direction:

- Pages express topic interest/subscriptions in page-owned code.
- Pages or page-adjacent domain code express how a successful save maps to broadcast topics/events.
- Generated Rally websocket glue consumes those declarations and handles the repetitive decode, authorize, call page handler, encode result, and broadcast-after-save plumbing.
- App root should not match page `ServerMsg` constructors or import page wire modules just to recover topic/event information.

## Topic Runtime Direction

Rally already has a BEAM `pg`-backed topic runtime. Keep `pg` as the low-level runtime mechanism: websocket handler processes join process groups, and broadcasts send frames to the group, excluding the initiating process when needed.

The author-facing API should probably be typed above that runtime boundary:

- Runtime transport can still collapse topics to stable group names.
- Page/domain code should not hand-roll arbitrary strings at every call site.
- A small typed topic value, constructor, or page-owned topic module can keep dynamic topic names explicit while preserving enough type information for generated Rally code.

Avoid a heavyweight global registry unless the first implementation proves it is needed.

## Additional Finding

`rally-scoreboard-example/src/app_api.gleam` is another part of the same boundary leak. It builds `broadcasts.GameSnapshot` from generated SQL rows and wraps it into `broadcasts.TargetedEvent` after admin saves. That is domain broadcast mapping, not root websocket API plumbing.

Preferred destination:

- Move game-updated snapshot construction and targeted-event mapping into `broadcasts.gleam`, page-adjacent admin save code, or another domain-owned module.
- Keep generated Rally websocket glue responsible for calling the broadcast mapping after a successful save.
- Keep `app_ws.gleam` and root modules out of generated SQL row-to-broadcast payload conversion.

## Root Module Scorecard

Scoring: `0` means keep as app-owned, `1` means mostly clean with minor watch items, `2` means cleanup planned or likely, `3` means active boundary leak for this cleanup direction.

| Module | Score | Why / Cleanup Direction |
| --- | ---: | --- |
| `src/admin_app.gleam` | 2 | Mostly a thin app shell/browser adapter now, but still owns dark-mode lifecycle calls and browser startup choreography. Dark-mode mechanics belong in Rally; shell UI remains app-owned. |
| `src/public_app.gleam` | 2 | Same as admin app: mostly generated browser glue consumption, but still owns dark-mode lifecycle and startup ceremony that can shrink after Rally owns persistence/application mechanics. |
| `src/app_api.gleam` | 3 | Root-level broadcast mapping leak. It converts generated SQL rows into broadcast payloads and targeted events. Move this into `broadcasts.gleam`, page-adjacent save/broadcast code, or a domain-owned module consumed by generated Rally glue. |
| `src/app_ws.gleam` | 3 | Active websocket boundary leak. Imports admin page module, wires page-specific load/save callbacks, matches page `ServerMsg`, and broadcasts manually. Rally should generate the mapping and call app/page-owned policy hooks. |
| `src/broadcasts.gleam` | 1 | Correct domain home for broadcast payloads and topic constructors. Needs typed topics and targeted-event construction centralized here; this is a destination, not root plumbing to remove. |
| `src/app_shell.gleam` | 0 | App-owned UI shell: nav, sign-in links, dark-mode toggle UI placement. Keep here, but storage/application mechanics should move out. |
| `src/authentication_context.gleam` | 0 | App/domain identity shape and display helpers. Keep app-owned unless template auth later introduces a shared minimal context boundary. |
| `src/page_context.gleam` | 1 | Empty/light marker used by generated page dispatch. Watch for whether Rally/Proute should own the default marker long term, but no active leak. |
| `src/page_stub.gleam` | 1 | Adapter scaffolding for generated/proute page types. Mostly framework-shaped, but harmless until Proute/Rally can remove the need for authored stubs. |
| `src/browser_mount.gleam` | 2 | App wrapper over generated Rally browser helpers only to pass app cookie/preferences. Should shrink or disappear when Rally owns dark-mode storage/application mechanics. |
| `src/device_preferences.gleam` | 2 | Generic device preference cookie encoding/parsing for dark mode. Move storage mechanics into Rally; keep only app CSS/UI meaning if anything remains. |
| `src/app_document.gleam` | 2 | Owns document shell, which is app-owned, but also parses device preference cookies and boot attrs. Dark-mode storage should move to Rally; auth boot attrs may shrink with template auth. |
| `src/app_ssr.gleam` | 1 | Much cleaner after generated admin/public SSR load context. Still bridges auth/session and shell rendering, which is mostly app-owned for now. Watch after template auth. |
| `src/scoreboard_unified.gleam` | 2 | Main server composition still owns config/session construction, auth route handling, websocket init, static routing, and HTTP shell. Some is app composition, but secret/port/session/auth plumbing should move into Rally/template runtime. |
| `src/app_config.gleam` | 2 | Secret key validation and port/env parsing are framework/template mechanics. DB path/defaults and app-specific env choices may remain app-owned. |
| `src/app_session.gleam` | 3 | Generic encrypted session cookie codec. Should move into Rally template auth. App should not own crypto/session serialization mechanics. |
| `src/app_auth_http.gleam` | 3 | Generic sign-in/sign-out/session-cookie HTTP plumbing. Product policy and user lookup stay app-owned, but handlers/cookie mechanics belong in Rally template auth. |
| `src/app_auth.gleam` | 2 | Mixed: user lookup/admin policy are app-owned, but sign-in code verification and session-cookie lookup are template-auth candidates. Split rather than delete. |

Highest-priority cleanup from this bean:

1. `app_ws.gleam`
2. `app_api.gleam`
3. `broadcasts.gleam` typed topic/targeted-event shape
4. page `topics` functions and broadcast update hooks
5. generated Rally websocket glue that consumes those declarations

Related but separate beans:

- `rally-mhn4`: template auth should handle `app_session.gleam`, much of `app_auth_http.gleam`, and part of `app_auth.gleam`.
- `rally-gvkf`: dark-mode storage/application should handle `browser_mount.gleam`, `device_preferences.gleam`, and parts of `admin_app.gleam`, `public_app.gleam`, and `app_document.gleam`.
