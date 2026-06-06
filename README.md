![Rally](https://github.com/pairshaped/rally/blob/master/rally.png?raw=true)

# Rally

[![Package Version](https://img.shields.io/hexpm/v/rally)](https://hex.pm/packages/rally)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/rally/)

Rally is a Gleam package for building Lustre apps that render on the server and hydrate in the browser. You write page modules with page-local models, messages, load handlers, save handlers, views, and broadcast hooks. Rally generates routing composition, server-side rendering, WebSocket transport, request/result protocol code, hydration, browser lifecycle, and typed client-server messaging.

The page file is the contract. Client state, server calls, and the message types that cross the wire all live together until you choose to extract shared code.

Rally apps use SQLite by default: embedded database, migrations, and type-safe SQL codegen, with no separate database server for development.

## What Rally Generates

Rally reads page modules and writes the routing, SSR, WebSocket transport, request and response encoding, and dispatch code around them.

You still write the UI, SQL, auth policy, and server handlers.

`rally build` follows the Rally Scoreboard unified-source path. It runs configured Marmot codegen, runs Proute when `proute.toml` exists, composes Proute routes with Libero codecs, writes `src/generated/rally/**` and `src/generated/libero/**`, then builds the current package for Erlang and JavaScript.

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

`rally migrate` delegates to `marmot migrate`, so Marmot owns the configured database path and migration directory. The starter uses `db/migrations` and stores local SQLite databases under `db/`. `rally build` then regenerates framework glue and builds the app for Erlang and JavaScript. Start the server with `gleam run -m rally server` and open `http://localhost:8080`. To use a different port, set `PORT` in `.env` or run `PORT=8081 gleam run -m rally server`. Run `rally migrate` before `rally build` and before deploying against a new database.

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

A page file in `src/<namespace>/pages/` is a Lustre component with server load
and save handlers beside the client UI:

```gleam
import gleam/int
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/effect.{type Effect}
import lustre/effect
import lustre/event
import generated/proute/public/page_input
import public/page_shared_state.{type PublicPageSharedState}
import rally/runtime/load as runtime_load

@target(javascript)
import generated/rally/server

@target(erlang)
import sqlight

pub type Model {
  Model(count: Int, error: String)
}

pub type Message {
  Increment
  Loaded(Result(Int, runtime_load.LoadError))
  Saved(Result(GameUpdate, SaveError))
}

pub type ServerMsg {
  PublicHomeLoad
  PublicHomeIncrement
}

pub type LoadResult {
  PublicHomeLoaded(count: Int)
}

pub type GameUpdate {
  GameUpdate(count: Int)
}

pub type SaveError {
  SaveError(message: String)
}

pub fn initial_model(
  _page_shared_state: PublicPageSharedState,
  _query_params: page_input.QueryParams,
) -> Model {
  Model(count: 0, error: "")
}

pub fn update(model: Model, msg: Message) -> #(Model, Effect(Message)) {
  case msg {
    Increment -> #(model, save_effect(Increment))
    Loaded(Ok(count)) -> #(Model(count:, error: ""), effect.none())
    Loaded(Error(error)) -> #(Model(..model, error: error.message), effect.none())
    Saved(Ok(GameUpdate(count:))) -> #(Model(count:, error: ""), effect.none())
    Saved(Error(SaveError(message:))) ->
      #(Model(..model, error: message), effect.none())
  }
}

pub fn view(model: Model) -> Element(Message) {
  html.main([], [
    html.button([event.on_click(Increment)], [
      html.text("Count: " <> int.to_string(model.count)),
    ]),
    case model.error {
      "" -> html.text("")
      message -> html.p([attribute.class("error")], [html.text(message)])
    },
  ])
}

@target(javascript)
fn save_effect(_msg: Message) -> Effect(Message) {
  server.save_public_home(
    message: PublicHomeIncrement,
    on_result: fn(result) {
      Saved(case result {
        Ok(update) -> Ok(update)
        Error(_) -> Error(SaveError(message: "Could not save counter."))
      })
    },
  )
}

@target(erlang)
pub fn load(db: sqlight.Connection) -> Result(Int, runtime_load.LoadError) {
  // Read from the database here.
  Ok(0)
}

@target(erlang)
pub fn handle(
  db: sqlight.Connection,
  message: ServerMsg,
) -> Result(GameUpdate, SaveError) {
  case message {
    PublicHomeLoad -> Error(SaveError(message: "Load is not a save action."))
    PublicHomeIncrement -> {
      // Write to the database here.
      Ok(GameUpdate(count: 1))
    }
  }
}
```

`Model`, `Message`, `initial_model`, `update`, and `view` are normal Lustre TEA. `ServerMsg`, `LoadResult`, `load`, and `handle` define the server boundary. Rally generates browser functions such as `generated/rally/server.save_public_home`, server dispatch, SSR loading, hydration, and WebSocket transport.

There is no separate API schema. Rally scans page-local handler signatures and wires them into generated browser and server code. Rally uses [Libero](https://hexdocs.pm/libero/) as its lower-level wire codec library, the same way Marmot-generated SQL access code uses SQLite underneath.

## File-based routing

The filename determines the URL:

| File | URL | Route variant |
|------|-----|--------------|
| `home_.gleam` or `index.gleam` | `/` | `Home` |
| `about.gleam` | `/about` | `About` |
| `products/id_.gleam` | `/products/:id` | `ProductsId(id: Int)` |
| `settings/profile.gleam` | `/settings/profile` | `SettingsProfile` |

A trailing `_` makes the segment dynamic. Params named `id` or ending in `_id` parse as `Int`; others parse as `String`.

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

Running `gleam run -m rally build` reads the app's standard project config and produces unified-source generated files:

- `src/generated/proute/**`: route types, route params, query params, and page dispatch, generated by Proute when `proute.toml` exists.
- `src/generated/rally/**`: request/result protocols, client transport, browser mount/app glue, hydration, SSR, websocket handling, theme helpers, and load/save result envelopes.
- `src/generated/libero/**`: ETF codec helpers, decoder registration, atoms/wire modules, and Libero contract metadata.

For broadcast-aware pages in the unified-source surface, app code owns typed topics and broadcast event payloads. Page `broadcast_subscriptions` and `apply_broadcast` hooks live together in a `// BROADCAST` section. Generated Rally glue maps typed topics to text topic sync frames, filters broadcasts on the server per connection, and calls page `apply_broadcast` hooks with decoded events.

## Examples

- [Rally Scoreboard](../rally-scoreboard-example/): unified-source Rally example with Proute routes, Libero codecs, page-local load/save contracts, typed broadcast topics, SSR, hydration, and browser navigation.

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

Rally depends on [Libero](https://hexdocs.pm/libero/) for wire encoding and decoding. Rally-generated code consumes Libero runtime modules directly, so Rally-managed apps list Libero as a runtime dependency. Projects that use Libero directly, or other frameworks built on Libero, can use Libero without Rally.

## Influences

- [Lamdera](https://lamdera.com): explicit server handler types as the contract, TEA on both sides
- [Lustre](https://lustre.build/): TEA, effects, and the client-side UI runtime
- [elm-land](https://elm.land): file-based routing conventions
- [Libero](https://hexdocs.pm/libero/): lower-level wire codec library used by Rally-generated code
- [Marmot](https://hexdocs.pm/marmot/): SQL-first codegen with live SQLite introspection

## License

MIT. See [LICENSE](https://github.com/pairshaped/rally-gleam/blob/master/LICENSE).
