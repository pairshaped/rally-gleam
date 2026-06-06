# Use Page Local Rally Contracts

## Status

Accepted

## Decision

Rally applications use one authored Gleam source tree. Page modules look like
ordinary Lustre TEA pages with Rally hooks beside the TEA core.

Page modules own their local `Model`, browser `Message`, page-local `ServerMsg`,
`initial_model`, optional `init`, `view`, `update`, optional broadcast hooks,
and Erlang-only server hooks.

The page filename and path are the author-facing routing surface. Route params
and query params arrive through generated Proute page input types. Authored page
code should not match generated route constructors, wrap itself in generated page
enums, or decide page load dispatch from routes.

## Function Contract

| Function or type | Status | Generated caller |
| --- | --- | --- |
| `initial_model` | Required for every page | `generated/proute/<mount>/pages` constructs empty page models for browser routing and SSR |
| `init` | Optional | `generated/proute/<mount>/pages` calls it when the route first builds a page that defines it |
| `update` | Required TEA page function | `generated/proute/<mount>/pages` forwards active page messages |
| `view` | Required TEA page function | `generated/proute/<mount>/pages` renders the active page |
| `ServerMsg` | Required for pages that load or save through Rally | Rally and Libero use it as the page-local server request payload |
| `LoadResult` | Required for pages that load through Rally | Rally and Libero use it as the page-local load result payload |
| `load` | Required for pages that use standard Rally page data loading | `generated/rally/server_ssr` and `generated/rally/server_ws` call it and wrap the result |
| `handle_save` | Required for pages that send page-local server commands | `generated/rally/server_ws` calls it after decoding a save command |
| `SaveError` | Required when `handle_save` exists | Rally maps it to generated save transport errors |
| `after_save` | Optional | `generated/rally/server_ws` calls it after a successful save when broadcasts are configured |
| `broadcast_subscriptions` | Required for broadcast-aware pages | `generated/rally/browser_app` syncs active broadcast topics |
| `apply_broadcast` | Required for broadcast-aware pages | `generated/rally/browser_app` applies decoded broadcast events |

`init` exists only when a page needs page-local browser startup work such as
browser APIs, local storage, focus, measurement, or one-off DOM effects.
Standard page data loading belongs to generated Rally glue.

## Load Contract

`ServerMsg` load constructors end in `Load`. Their labelled fields are the load
arguments. `LoadResult` has one constructor and defines the page-local wire
payload returned by `load`.

```gleam
pub type ServerMsg {
  PublicGameDetailLoad(game_id: Int)
}

pub type LoadResult {
  PublicGameDetailLoaded(game: GameDetail)
}

@target(erlang)
pub fn load(
  db: sqlight.Connection,
  route_params: page_input.GamesIdRouteParams,
) -> Result(GameDetail, runtime_load.LoadError)
```

Rally discovers the load contract from `ServerMsg`, `LoadResult`, and `load`.
It generates SSR adapters, browser navigation adapters, protocol wrappers,
transport code, and typed result decoding.

## Save Contract

A page has a save contract when its `ServerMsg` includes at least one
constructor whose name does not end in `Load` and the page exports `handle_save`.

Rally discovers the save payload from the annotated return type of `handle_save`.
The `Ok` type must be a non-generic custom type defined in the page's wire
module.

```gleam
pub type ServerMsg {
  PublicHomeLoad
  PublicHomeIncrement
}

pub type CounterUpdate {
  CounterUpdate(count: Int)
}

pub type SaveError {
  SaveError(message: String)
}

@target(erlang)
pub fn handle_save(
  db: sqlight.Connection,
  message: ServerMsg,
) -> Result(CounterUpdate, SaveError)
```

The save payload name is application-owned. Rally does not require names such as
`GameUpdate`; it matches the `Result` shape and uses the page-local `Ok` type as
the payload for generated save result codecs and browser save callbacks.

Browser page code sends saves through generated page-specific functions such as
`generated/rally/server.save_admin_games`.

## Consequences

The page file is the contract. There is no separate API schema, route handler
table, generated client app package, or app-owned root module that forwards page
messages into Rally.

Rally validates function names, signatures, target availability, and
wire-visible types. Human section comments such as `// BROADCAST` and
`// SERVER` are useful style, but they are not the contract.
