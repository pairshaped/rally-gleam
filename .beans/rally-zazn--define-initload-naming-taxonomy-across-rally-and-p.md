---
# rally-zazn
title: Reduce init/load lifecycle surface across Rally and Proute
status: in-progress
type: task
priority: normal
created_at: 2026-06-06T02:40:29Z
updated_at: 2026-06-06T03:11:20Z
---

## Problem

Rally and Proute now expose too many nearby lifecycle hooks and generated pathways: `init`, `initial_model`, `init_page`, `initial_page`, `load`, `load_sync`, load RPC modules, SSR boot loaders, websocket page init, and generated load adapters. Naming is part of the problem, but the deeper issue is API surface area: app authors should not need to define or understand several nearly identical hooks just to get one page working in browser, SSR, and websocket flows.

The framework should infer or generate more of this lifecycle when it is mechanical. Authored page modules should express product behavior: initial page state, data loading, update, view, topics, and domain event handling. Generated code should handle browser mount startup, SSR fallback, hydration, load transport, websocket setup, and effect mapping without requiring duplicate page hooks unless the page genuinely has different behavior.

## Desired Outcome

Design and implement a smaller page lifecycle contract. The goal is fewer authored functions, less handwritten wiring, and a clearer separation between page-owned product behavior and framework-owned runtime mechanics.

Questions to answer:

- Can `initial_model` be generated or made optional from `Model(...)` defaults, page `load`, or another narrower convention?
- Can `init` be generated from `initial_model` plus optional page load metadata, instead of every page defining both?
- Should SSR use the same page construction path as browser startup and then layer loaded data in, instead of requiring separate `load_sync` naming/API concepts?
- Which functions are app-authored page hooks, which are generated Proute page dispatch, and which are Rally runtime boot/load plumbing?
- What is the smallest contract that still supports route params, query params, page shared state, SSR fallback, hydration, websocket loads, browser effects, and route-backed topics?

## Acceptance Criteria

- [ ] Audit Rally, Proute, and Scoreboard for public/generated functions and modules involved in init, initial model creation, load, load sync, SSR boot, hydration, websocket page init, and load RPC.
- [ ] Classify each function as app-authored product behavior, generated Proute page construction, generated Rally runtime plumbing, or removable/mergeable duplication.
- [ ] Propose a smaller page lifecycle contract, including which page functions are required, optional, or generated.
- [ ] Update ADR/docs with the reduced lifecycle model and terminology.
- [ ] Implement the first safe reduction in authored page functions or generated wiring.
- [ ] Update Scoreboard to prove the reduced contract is nicer in real app code.
- [ ] Update snapshots/tests/examples after any lifecycle contract change.

## Non-goals

- Do not rename functions only to make the current large surface look cleaner.
- Do not collapse data loading and page construction if that hides product behavior or breaks SSR/hydration clarity.
- Do not remove a hook until browser, SSR, websocket, route params, query params, and page shared state still have a clear path.


## Investigation Notes

Current Scoreboard loadable pages commonly define all of these:

- `init`: calls `initial_model` plus a JS-only load effect.
- `initial_model`: pure empty/fallback model used by generated Proute `load_sync`.
- `init_effect` twice: JavaScript sends a generated load RPC; Erlang returns `effect.none()`.
- `map_load_result`: JavaScript maps generated API load errors into page-local `LoadError`.
- `loaded_from_wire`: Erlang maps SSR load results into page `Message`.
- `*_loaded`: page-local reducer helper for loaded data.
- `load`: server-side data query used by generated SSR and websocket load handlers.

Findings:

- Rally-generated browser startup and navigation already bypass page `init` for load-RPC pages. They use `generated/proute/{mount}/pages.load_sync(...)` to build the empty page, then generated Rally request/hydration code loads data and applies the resulting page message.
- Rally-generated SSR also bypasses page `init`: it uses `pages.load_sync(...)`, runs the server `load`, then applies a loaded message through generated page update.
- Proute-generated generic `pages.load(...)` still calls page `init`, but the Scoreboard Rally app path does not depend on it for load-RPC pages.
- The page-local `*_loaded` helpers in Scoreboard appear unused by generated code and by page update functions. They are dead ceremony unless a future generator starts calling them.
- `loaded_from_wire` is only needed because generated SSR currently calls a page-authored adapter. The browser generator already constructs `Loaded(Ok(data))` and `Loaded(Error(LoadError(...)))` directly, so SSR could generate the same shape and remove this hook from pages.
- `map_load_result` and the JS/Erlang `init_effect` pair are only needed by page `init`. If Rally apps stop requiring page `init` for load-RPC pages, those disappear from authored pages too.

Likely first reduction:

- Make Proute page `init` optional. If absent, generated `pages.load(...)` can fall back to `initial_model(...)` plus `effect.none()`.
- Keep `initial_model` required for now because SSR/browser need a pure page value and Proute cannot safely synthesize arbitrary model constructors.
- Update Rally SSR generation to build loaded messages directly instead of calling page `loaded_from_wire`.
- Delete dead `*_loaded`, `loaded_from_wire`, `map_load_result`, `init_effect`, and most page `init` functions from Scoreboard where generated Rally load RPC owns the request effect.

Open design question:

- Pages without load RPC but with real browser-only startup effects still need an authored `init`. That argues for optional `init`, not removing `init` from the Proute contract entirely.



## Progress

- Implemented the first safe reduction: Proute page `init` is optional and falls back to `initial_model` plus `effect.none()`.
- Rally browser load-RPC glue now uses generated Proute `pages.load(...)`, so optional page `init` effects run on browser startup and navigation.
- Rally SSR generation maps load results into page `Loaded` messages directly, removing the authored `loaded_from_wire` hook from example pages.
- Scoreboard now removes no-op `init`, `init_effect`, `map_load_result`, `loaded_from_wire`, and one-line loaded helpers from load-RPC pages.
- The public game detail page keeps `init` as the example escape hatch and uses it for a browser alert effect, while standard page data loading stays in generated Rally glue.
- Updated Proute, Rally, and Scoreboard docs to describe `initial_model` as the normal page entry point and `init` as optional client startup work.

Remaining in this bean: decide whether `initial_model` can shrink further or whether this is the right stable minimum for now.



## Decision

Do not keep `loaded_from_wire` as an escape hatch. It is transport-shaped and SSR-specific, so it leaks generated wire plumbing into page code. The current convention is that Rally maps load results into the page-owned `Loaded(Result(data, LoadError))` message shape. If a future page needs custom load-result interpretation, add a symmetric page lifecycle hook that works for browser and SSR instead of reviving `loaded_from_wire`.



## Progress

- Renamed generated Proute `pages.load_sync(...)` to `pages.initial_page(...)` because it constructs the pure page value and does not load data.
- Updated Rally SSR generation to call `initial_page(...)` before layering server-loaded data and hydration onto the page.
- Regenerated Scoreboard Proute and Rally generated files; the old `load_sync` name is gone across Proute, Rally, and Scoreboard.

Decision: keep authored `initial_model` required for now. Proute cannot safely synthesize arbitrary page model constructors, and SSR needs a pure model path that does not run optional browser startup effects from `init`.
