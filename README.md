![Rally](https://github.com/pairshaped/rally/blob/master/rally.png?raw=true)

# Rally

[![Package Version](https://img.shields.io/hexpm/v/rally)](https://hex.pm/packages/rally)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/rally/)

Rally is a Gleam package for building Lustre apps that render on the server and hydrate in the browser. You write page modules with page-local models, messages, load handlers, save handlers, views, and broadcast hooks. Rally generates routing composition, server-side rendering, WebSocket transport, request/result protocol code, hydration, browser lifecycle, and typed client-server messaging.

The page file is the contract. Client state, server calls, and the message types that cross the wire all live together until you choose to extract shared code.

Rally is opinionated. It chooses conventions so application code can stay small, generated code can stay predictable, and the framework can test the common path hard. A Rally app uses SQLite, Marmot, Proute, and Libero as part of that path. If an app needs a different foundation, fork Rally and submit a tested PR instead of growing local framework glue.

## Convention Stack

| Library | What Rally uses it for |
|---|---|
| SQLite | Embedded application database |
| Marmot | SQL migrations and type-safe query generation from `.sql` files |
| Proute | File-based routes, route params, query params, page enums, and page dispatch |
| Libero | Typed wire codecs for page-local load/save contracts and broadcasts |
| Lustre | Browser-side TEA views, updates, and effects |

## What Rally Generates

Rally reads page modules and writes the routing, SSR, WebSocket transport, request and response encoding, and dispatch code around them.

You still write the UI, SQL, auth policy, and server handlers.

`rally build` follows the Rally Scoreboard Example path. It runs configured Marmot codegen, runs Proute when `proute.toml` exists, composes Proute routes with Libero codecs, writes `src/generated/rally/**` and `src/generated/libero/**`, then builds the current package for Erlang and JavaScript.

## Create an app

```sh
gleam new my_app
cd my_app
gleam add rally libero
gleam run -m rally init
gleam run -m rally migrate
gleam run -m rally build
gleam run
```

`rally init` writes the starter app into the current Gleam project, including `src/my_app.gleam`. It replaces the default files from `gleam new` that Rally needs to take over: `gleam.toml`, `.gitignore`, `README.md`, and `src/my_app.gleam`. If you already wrote your own `README.md`, Rally leaves it alone. If any other target file already exists, Rally stops before writing anything and tells you which file needs attention.

`rally migrate` delegates to `marmot migrate`; Rally has no migration runner of its own. Marmot owns the configured database path and migration directory. The starter uses `db/migrations` and stores local SQLite databases under `db/`. `rally build` then regenerates framework glue and builds the app for Erlang and JavaScript. Start the server with `gleam run -m rally server` and open `http://localhost:8080`. To use a different port, set `PORT` in `.env` or run `PORT=8081 gleam run -m rally server`. Run `rally migrate` before `rally build` and before deploying against a new database.

Common workflow commands:

| Command | What it does |
|---|---|
| `gleam run -m rally gen` | Runs Marmot, Proute, Rally, and Libero codegen without building |
| `gleam run -m rally regen` | Deletes `src/generated` and then runs `gen` |
| `gleam run -m rally build` | Runs `gen`, then builds Erlang and JavaScript targets |
| `gleam run -m rally migrate` | Delegates to `marmot migrate` |
| `gleam run -m rally reset` | Delegates to `marmot reset`, including seeds |
| `gleam run -m rally server` | Stops any process on `PORT` or 8080, then runs `gleam run` in the foreground |

## Writing a page

A page file in `src/<namespace>/pages/` is a Lustre component with Rally load,
save, and broadcast hooks beside the client UI. A shortened admin games page
looks like this:

```gleam
import admin/page_shared_state.{type AdminPageSharedState}
import broadcasts
import generated/proute/admin/page_input
import gleam/int
import gleam/list
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rally/runtime/load as runtime_load

@target(javascript)
import generated/rally/server

@target(erlang)
import generated/sql/admin/pages/games_sql
@target(erlang)
import sqlight

pub type GameStatus {
  Scheduled
  Live(period: String)
  Final
}

pub type AdminGameSummary {
  AdminGameSummary(
    id: Int,
    home_code: String,
    away_code: String,
    home_score: Int,
    away_score: Int,
    status: GameStatus,
  )
}

pub type GameUpdate {
  GameUpdate(
    id: Int,
    home_code: String,
    away_code: String,
    home_score: Int,
    away_score: Int,
    status: GameStatus,
  )
}

pub type LoadResult {
  AdminGamesLoadResult(games: List(AdminGameSummary))
}

pub type ServerMsg {
  AdminGamesLoad
  AdminGamesUpdateScore(
    game_id: Int,
    home_score: Int,
    away_score: Int,
    period: String,
  )
}

pub type SaveError {
  SaveError(message: String)
}

pub type Model {
  Model(games: List(AdminGameSummary), error: String)
}

pub type Message {
  AdjustHome(id: Int, home_score: Int, away_score: Int, delta: Int)
  Loaded(Result(List(AdminGameSummary), runtime_load.LoadError))
  Saved(Result(GameUpdate, SaveError))
}

pub fn initial_model(
  _page_shared_state: AdminPageSharedState,
  _query_params: page_input.QueryParams,
) -> Model {
  Model(games: [], error: "")
}

pub fn update(
  _page_shared_state: AdminPageSharedState,
  model: Model,
  msg: Message,
) -> #(Model, Effect(Message)) {
  case msg {
    AdjustHome(..) -> #(model, message_effect(msg))
    Loaded(Ok(games)) -> #(Model(games:, error: ""), effect.none())
    Loaded(Error(error)) -> #(Model(..model, error: error.message), effect.none())
    Saved(Ok(game)) -> #(upsert_game(model, game), effect.none())
    Saved(Error(SaveError(message:))) ->
      #(Model(..model, error: message), effect.none())
  }
}

pub fn view(model: Model) -> Element(Message) {
  html.main([], [
    html.div(
      [attribute.class("game-grid")],
      list.map(model.games, view_game_card),
    ),
    case model.error {
      "" -> html.text("")
      message -> html.p([attribute.class("error")], [html.text(message)])
    },
  ])
}

fn view_game_card(game: AdminGameSummary) -> Element(Message) {
  html.article([attribute.class("game-card")], [
    html.strong([], [html.text(game.home_code)]),
    html.span([], [html.text(int.to_string(game.home_score))]),
    html.button(
      [
        event.on_click(AdjustHome(
          id: game.id,
          home_score: game.home_score,
          away_score: game.away_score,
          delta: 1,
        )),
      ],
      [html.text("+")],
    ),
  ])
}

// BROADCAST

pub fn broadcast_subscriptions(_model: Model) -> List(broadcasts.Topic) {
  [broadcasts.admin_games_topic()]
}

pub fn apply_broadcast(
  model: Model,
  message: broadcasts.Event,
) -> #(Model, Effect(Message)) {
  case message {
    broadcasts.BroadcastGameUpdated(game) ->
      #(upsert_game(model, update_from_broadcast(game)), effect.none())
  }
}

@target(javascript)
fn message_effect(msg: Message) -> Effect(Message) {
  case msg {
    AdjustHome(id, home_score, away_score, delta) ->
      server.save_admin_games(
        message: AdminGamesUpdateScore(
          game_id: id,
          home_score: clamp_score(home_score + delta),
          away_score: away_score,
          period: "Live",
        ),
        on_result: fn(result) { Saved(map_save_result(result)) },
      )
    Loaded(_) | Saved(_) -> effect.none()
  }
}

@target(erlang)
fn message_effect(_msg: Message) -> Effect(Message) {
  effect.none()
}

fn upsert_game(model: Model, game: GameUpdate) -> Model {
  let games =
    list.map(model.games, fn(existing) {
      case existing.id == game.id {
        True ->
          AdminGameSummary(
            id: game.id,
            home_code: game.home_code,
            away_code: game.away_code,
            home_score: game.home_score,
            away_score: game.away_score,
            status: game.status,
          )
        False -> existing
      }
    })

  Model(..model, games:)
}

@target(javascript)
fn map_save_result(
  result: Result(GameUpdate, List(server.SaveError)),
) -> Result(GameUpdate, SaveError) {
  case result {
    Ok(game) -> Ok(game)
    Error([server.SaveError(message: message, ..), ..]) ->
      Error(SaveError(message:))
    Error([]) -> Error(SaveError(message: "Could not save game."))
  }
}

fn update_from_broadcast(game: broadcasts.GameSnapshot) -> GameUpdate {
  let broadcasts.BroadcastGameSnapshot(
    id:,
    home: broadcasts.BroadcastTeam(code: home_code, ..),
    away: broadcasts.BroadcastTeam(code: away_code, ..),
    home_score:,
    away_score:,
    status:,
  ) = game

  GameUpdate(
    id:,
    home_code:,
    away_code:,
    home_score:,
    away_score:,
    status: game_status_from_broadcast(status),
  )
}

fn game_status_from_broadcast(status: broadcasts.GameStatus) -> GameStatus {
  case status {
    broadcasts.BroadcastScheduled -> Scheduled
    broadcasts.BroadcastLive(period) -> Live(period)
    broadcasts.BroadcastFinal -> Final
  }
}

fn clamp_score(score: Int) -> Int {
  case score < 0 {
    True -> 0
    False -> score
  }
}

@target(erlang)
pub fn load(
  db: sqlight.Connection,
) -> Result(List(AdminGameSummary), runtime_load.LoadError) {
  case games_sql.list_admin_games(db:) {
    Ok(rows) -> Ok(list.map(rows, game_from_row))
    Error(sqlight.SqlightError(..)) ->
      Error(runtime_load.LoadError(message: "Could not load games."))
  }
}

@target(erlang)
pub fn handle(
  db: sqlight.Connection,
  msg: ServerMsg,
) -> Result(GameUpdate, SaveError) {
  case msg {
    AdminGamesLoad -> Error(SaveError(message: "Load is not a save action."))
    AdminGamesUpdateScore(game_id, home_score, away_score, period) ->
      case
        games_sql.update_game_score(
          db:,
          game_id:,
          home_score:,
          away_score:,
          period:,
        )
      {
        Ok([row, ..]) -> Ok(game_update_from_row(row))
        Ok([]) -> Error(SaveError(message: "Game not found."))
        Error(sqlight.SqlightError(..)) ->
          Error(SaveError(message: "Could not save game."))
      }
  }
}

@target(erlang)
pub fn after_save(
  db: sqlight.Connection,
  game: GameUpdate,
) -> Result(broadcasts.TargetedEvent, Nil) {
  broadcasts.game_updated_broadcast(db, game.id)
}

@target(erlang)
fn game_from_row(row: games_sql.ListAdminGamesRow) -> AdminGameSummary {
  AdminGameSummary(
    id: row.id,
    home_code: row.home_code,
    away_code: row.away_code,
    home_score: row.home_score,
    away_score: row.away_score,
    status: game_status(row.period, row.final),
  )
}

@target(erlang)
fn game_update_from_row(row: games_sql.UpdateGameScoreRow) -> GameUpdate {
  GameUpdate(
    id: row.id,
    home_code: row.home_code,
    away_code: row.away_code,
    home_score: row.home_score,
    away_score: row.away_score,
    status: game_status(row.period, row.final),
  )
}

@target(erlang)
fn game_status(period: String, final: Int) -> GameStatus {
  case final == 1, period {
    True, _ -> Final
    False, "Scheduled" -> Scheduled
    False, _ -> Live(period)
  }
}
```

`Model`, `Message`, `initial_model`, `update`, and `view` are normal Lustre TEA, with `AdminPageSharedState` passed into page lifecycle functions for app-wide browser state. `ServerMsg`, `LoadResult`, `load`, optional `handle`, and optional `after_save` define the server boundary. `broadcast_subscriptions` and `apply_broadcast` define live update interest. Rally generates browser functions such as `generated/rally/server.save_admin_games`, server dispatch, SSR loading, hydration, topic sync, and WebSocket transport.

There is no separate API schema. Rally scans page-local handler signatures and wires them into generated browser and server code. Rally uses [Libero](https://hexdocs.pm/libero/) as its lower-level wire codec library, the same way Marmot-generated SQL access code uses SQLite underneath.

## File-based routing

The filename determines the URL:

| File | URL | Route variant |
|------|-----|--------------|
| `home_.gleam` | `/` | `Home` |
| `about.gleam` | `/about` | `About` |
| `games.gleam` | `/games` | `Games` |
| `products/id_.gleam` | `/products/:id` | `ProductsId(id: Int)` |
| `settings/profile.gleam` | `/settings/profile` | `SettingsProfile` |

`home_.gleam` is the default route for the directory it lives in. A trailing `_` makes the segment dynamic. Params named `id` or ending in `_id` parse as `Int`; others parse as `String`.

## What to import

Most Rally apps use only a few modules directly:

| Module | Use it for |
|---|---|
| `rally/runtime/load` | Standard page load error type |
| `rally/runtime/db` | SQLite open, timed queries, nested transactions, SQL value helpers |
| `rally/runtime/system` | App startup and background jobs |
| `rally/runtime/session` | Session cookie generation, parsing, response headers |
| `rally/runtime/auth` | Auth policy types, load result types, secret hashing, login codes |
| `rally/runtime/auth_http` | Standard sign-in, sign-out, email-code, and Google provider HTTP routes |
| `rally/runtime/env` | `APP_ENV` parsing and production cookie policy |
| `rally/runtime/test_db` | Fast in-memory SQLite for tests |

The `rally/internal/...` modules are codegen implementation. App code should treat them as private. The generated files under `src/generated/` are the boundary Rally presents to your app.

### Auth helpers

`rally/runtime/auth` contains the shared types Rally expects for page auth, plus helpers for common auth flows. `auth.hash` stores passwords or other submitted secrets with PBKDF2-SHA256 using Erlang/OTP crypto. `auth.verify` checks a submitted secret against a stored hash.

For short login-code flows, use `auth.generate_login_code`, then store `auth.hash_login_code(scope:, code:, secret_key:)`. Later, check the submitted code with `auth.verify_login_code(stored:, scope:, code:, secret_key:)`. The scope is usually an email address or another app-owned lookup value. Rally trims and lowercases both the scope and the code before hashing. The `secret_key` should be a stable app secret that is not stored in the database.

`rally/runtime/auth_http` owns the standard provider route mechanics. The email-code flow uses `POST /sign_in/code` to ask the app to deliver a code for an email, then `POST /sign_in` verifies a submitted code and issues the Rally auth session. The Google flow uses `/sign_in/google` and `/sign_in/google/callback` for provider redirect, state cookies, and session issuing after the app exchanges the provider code and returns a local user id. Apps provide callbacks for user lookup/upsert, code storage/delivery, OAuth credentials, provider identity verification, return-path narrowing, and authorization policy.

## Generated files

Running `gleam run -m rally build` reads the app's standard project config and produces Rally Scoreboard Example generated files:

- `src/generated/proute/**`: route types, route params, query params, and page dispatch, generated by Proute when `proute.toml` exists.
- `src/generated/rally/**`: request/result protocols, client transport, browser mount/app glue, hydration, SSR, websocket handling, theme helpers, and load/save result envelopes.
- `src/generated/libero/**`: ETF codec helpers, decoder registration, atoms/wire modules, and Libero contract metadata.

For broadcast-aware pages in the Rally Scoreboard Example surface, app code owns typed topics and broadcast event payloads. Page `broadcast_subscriptions` and `apply_broadcast` hooks live together in a `// BROADCAST` section. Generated Rally glue maps typed topics to text topic sync frames, filters broadcasts on the server per connection, and calls page `apply_broadcast` hooks with decoded events.

## Examples

- [Rally Scoreboard](https://github.com/pairshaped/rally-scoreboard-example): definitive Rally Scoreboard Example app with Proute routes, Libero codecs, page-local load/save contracts, typed broadcast topics, SSR, hydration, and browser navigation.

## More docs

- [Pages](https://github.com/pairshaped/rally-gleam/blob/master/pages/guides/pages.md): routing, page lifecycle, SSR loading, and layouts
- [Server messaging](https://github.com/pairshaped/rally-gleam/blob/master/pages/guides/server-messaging.md): page-local load/save handlers and typed broadcasts
- [Runtime](https://github.com/pairshaped/rally-gleam/blob/master/pages/guides/runtime.md): the `rally/runtime/*` modules app code imports
- [Configuration](https://github.com/pairshaped/rally-gleam/blob/master/pages/guides/configuration.md): `gleam.toml`, generated paths, and protocols
- [Comparisons](https://github.com/pairshaped/rally-gleam/blob/master/pages/reference/comparisons.md): Rally, Lustre server components, and Lamdera-style apps
- [Internals](https://github.com/pairshaped/rally-gleam/blob/master/pages/reference/internals.md): codegen pipeline and contributor reading order
- [llms.txt](https://raw.githubusercontent.com/pairshaped/rally-gleam/refs/heads/master/llms.txt): raw context for language models

## Contributing

Rally is a Gleam project targeting Erlang. You need Gleam (v1.x), Erlang/OTP 26+, SQLite3, and Node.js.

```sh
git clone <repo-url>
cd rally
gleam build
gleam test
```

## Influences

- [Lamdera](https://lamdera.com): explicit server handler types as the contract, TEA on both sides
- [Lustre](https://lustre.build/): TEA, effects, and the client-side UI runtime
- [elm-land](https://elm.land): file-based routing conventions

## License

MIT. See [LICENSE](https://github.com/pairshaped/rally-gleam/blob/master/LICENSE).
