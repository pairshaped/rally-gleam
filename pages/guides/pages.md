# Pages

Rally pages are Lustre TEA modules under `src/<mount>/pages/`. Each page owns
its browser model, messages, update function, view, and any page-local server
contract.

The Rally Scoreboard example is the reference shape. Proute reads the page tree
and generates route params, query params, page enums, and page dispatch. Rally
reads the page contracts and generates SSR, hydration, browser navigation,
WebSocket transport, load/save dispatch, and topic sync.

## Required Exports

Every page exports the normal Lustre surface:

| Export | Purpose |
| --- | --- |
| `pub type Model` | Browser state for the page |
| `pub type Message` | Browser messages for the page |
| `pub fn initial_model(...)` | Pure starting model for SSR and browser boot |
| `pub fn update(...)` | Handle browser messages |
| `pub fn view(...)` | Render Lustre elements |

For a static route, `initial_model` receives page shared state and query params:

```gleam
pub fn initial_model(
  page_shared_state: PublicPageSharedState,
  query_params: page_input.QueryParams,
) -> Model
```

For a dynamic route, generated route params come between page shared state and
query params:

```gleam
pub fn initial_model(
  page_shared_state: PublicPageSharedState,
  route_params: page_input.GamesIdRouteParams,
  query_params: page_input.QueryParams,
) -> Model
```

Page shared state is app-defined per mount in
`src/<mount>/page_shared_state.gleam`. It is for values pages should see when
building their starting model. Shell-only browser state, such as dark mode or
the active path, belongs in the app shell and generated mount config.

## Optional Init

Use `init` when a page needs a browser-side effect at startup, such as focusing
an input, calling a JavaScript FFI hook, or starting a client-only subscription.
Most pages can skip it. The generated Proute page module for the mount calls
`init` when the route first builds the page.

```gleam
pub fn init(
  page_shared_state: PublicPageSharedState,
  route_params: page_input.GamesIdRouteParams,
  query_params: page_input.QueryParams,
) -> #(Model, Effect(Message)) {
  #(
    initial_model(page_shared_state, route_params, query_params),
    alert_effect(route_params.id),
  )
}
```

When `init` is absent, generated Rally glue calls `initial_model` and uses
`effect.none()`.

## File-Based Routing

| File | URL | Route variant |
| --- | --- | --- |
| `home_.gleam` | `/` | `Home` |
| `about.gleam` | `/about` | `About` |
| `products/id_.gleam` | `/products/:id` | `ProductsId(id: Int)` |
| `teams/slug_.gleam` | `/teams/:slug` | `TeamsSlug(slug: String)` |

`home_.gleam` is the default route for the directory it lives in. A file or
directory segment ending in `_` becomes a dynamic parameter. Params named `id`
or ending in `_id` parse as `Int`; other params parse as `String`.

## Loading Data

Pages can export Erlang-targeted `load` when SSR or browser navigation needs
server data before rendering the page.

```gleam
pub type LoadResult {
  PublicGamesIdLoaded(game: GameDetail)
}

@target(erlang)
pub fn load(
  db: sqlight.Connection,
  route_params: page_input.GamesIdRouteParams,
) -> Result(GameDetail, runtime_load.LoadError) {
  games.get(db, route_params.id)
}
```

Rally calls `load` during SSR, encodes the result through Libero, embeds
hydration flags in the HTML, and uses the same typed result during browser
navigation. Page `update` handles the generated loaded message and merges it
into the model.

## Saving Data

Use a page-local `ServerMsg` and `handle_save` for server work triggered by browser
events.

```gleam
pub type ServerMsg {
  AdminGamesHomeScore(game_id: Int)
}

pub type SaveError {
  SaveError(message: String)
}

@target(erlang)
pub fn handle_save(
  db: sqlight.Connection,
  message: ServerMsg,
) -> Result(GameUpdate, SaveError) {
  case message {
    AdminGamesHomeScore(game_id:) -> games.increment_home(db, game_id)
  }
}
```

On the browser target, generated Rally modules expose page-specific functions
such as `generated/rally/server.save_admin_games`.

## Broadcasts

Broadcast-aware pages define typed topics and event payloads in app code, often
in `broadcasts.gleam`.

```gleam
// BROADCAST

pub fn broadcast_subscriptions(model: Model) -> List(broadcasts.Topic) {
  case model.game {
    Some(game) -> [broadcasts.game_topic(game.id)]
    None -> []
  }
}

pub fn apply_broadcast(
  model: Model,
  event: broadcasts.Event,
) -> #(Model, Effect(Message)) {
  // Merge decoded broadcast data into the page model.
}
```

Rally maps typed topics to compact text frames, keeps subscription state per
connection, filters broadcasts on the server, and skips sending a broadcast back
to the initiating connection.

## Shells

App shell code lives outside the page tree, usually in `src/app_shell.gleam`.
It owns shared chrome such as navigation, theme controls, and wrappers around
page content. Generated SSR and browser mount code call the shell while page
modules stay focused on page state and page UI.
