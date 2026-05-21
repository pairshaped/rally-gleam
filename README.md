**THIS PROJECT IS NOT MAINTAINED**

![Rally](https://github.com/pairshaped/rally/blob/master/rally.png?raw=true)

# Rally

[![Package Version](https://img.shields.io/hexpm/v/rally)](https://hex.pm/packages/rally)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/rally/)

Rally is a Gleam package for building Lustre apps that render on the server and hydrate in the browser. You write page modules and `server_*` handler functions. Rally generates routing, server-side rendering, WebSocket transport, and typed client-server messaging.

The page file is the contract. Client state, server calls, and the message types that cross the wire all live together until you choose to extract shared code.

Rally apps use SQLite by default: embedded database, migrations, and type-safe SQL codegen, with no separate database server for development.

## What Rally Generates

Rally reads page modules and writes the routing, SSR, WebSocket transport, request and response encoding, and dispatch code around them.

You still write the UI, SQL, auth policy, and server handlers.

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

`rally migrate` applies SQLite migrations from `migrations/`, creates local databases under `db/`, and runs Marmot SQL codegen. `rally build` then generates the routing, SSR, and transport code and builds the JavaScript client. Start the server with `gleam run` and open `http://localhost:8080`. The starter is a counter that persists in SQLite: the value survives page refreshes because clicks go through RPC to the database. To use a different port, set `PORT` in `.env` or run `PORT=8081 gleam run`. Run `rally migrate` before `rally build` and before deploying against a new database.

## Writing a page

A page file in `src/<namespace>/pages/` is a Lustre component with server calls:

```gleam
import gleam/int
import lustre/element.{type Element, text}
import lustre/element/html
import rally_runtime/effect.{type Effect}
import rally_runtime/effect
import server_context.{type ServerContext}

// MODEL -- client state for this page.

pub type Model {
  Model(count: Int)
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(count: 0), effect.none())
}

// UPDATE -- client messages and how they change the model.

pub type Msg {
  Increment
  GotIncrement(Result(Int, List(String)))
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Increment ->
      // effect.rpc sends ServerIncrement to server_increment and
      // routes the response back through GotIncrement.
      #(model, effect.rpc(ServerIncrement(amount: 1), on_response: GotIncrement))

    GotIncrement(Ok(amount)) ->
      #(Model(count: model.count + amount), effect.none())

    GotIncrement(Error(_)) ->
      #(model, effect.none())
  }
}

// VIEW -- shared by server (SSR) and client (SPA).

pub fn view(model: Model) -> Element(Msg) {
  html.button([], [text("Count: " <> int.to_string(model.count))])
}

// SERVER -- message type and handler.
// Libero scans the handler signature to generate the wire contract.

pub type ServerIncrement {
  ServerIncrement(amount: Int)
}

pub fn server_increment(
  msg msg: ServerIncrement,
  server_context _server_context: ServerContext,
) -> Result(Int, List(String)) {
  Ok(msg.amount)
}
```

`Model`, `Msg`, `init`, `update`, and `view` are normal Lustre TEA. `ServerIncrement` and `server_increment` define the server call. The client sends the typed message with `effect.rpc`.

There is no separate API schema. [Libero](https://hexdocs.pm/libero/) scans the handler signature and Rally wires it into the generated client and server code.

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
| `rally_runtime/effect` | Page effects: RPC, server messages, navigation, broadcast, client context updates |
| `rally_runtime/db` | SQLite open, timed queries, nested transactions, SQL value helpers |
| `rally_runtime/system` | App startup and background jobs |
| `rally_runtime/session` | Session cookie generation, parsing, response headers |
| `rally_runtime/auth` | Auth policy types, load result types, secret hashing, login codes |
| `rally_runtime/env` | `APP_ENV` parsing and production cookie policy |
| `rally_runtime/migrate` | Numbered SQLite migrations |
| `rally_runtime/test_db` | Fast in-memory SQLite for tests |

The `rally/internal/...` modules are codegen implementation. App code should treat them as private. The generated files under `src/generated/` are the boundary Rally presents to your app.

### Auth helpers

`rally_runtime/auth` contains the shared types Rally expects for page auth, plus helpers for common auth flows. `auth.hash` stores passwords or other submitted secrets with PBKDF2-SHA256 using Erlang/OTP crypto. `auth.verify` checks a submitted secret against a stored hash.

For short login-code flows, use `auth.generate_login_code`, then store `auth.hash_login_code(scope:, code:, secret_key:)`. Later, check the submitted code with `auth.verify_login_code(stored:, scope:, code:, secret_key:)`. The scope is usually an email address or another app-owned lookup value. Rally trims and lowercases both the scope and the code before hashing. The `secret_key` should be a stable app secret that is not stored in the database.

## Generated files

Running `gleam run -m rally` reads `[[tools.rally.clients]]` from gleam.toml and produces:

**Server-side** (in `src/generated/<namespace>/`): router, page dispatch, RPC dispatch, SSR handler, WebSocket handler, HTTP handler, protocol wire facade.

**Client-side** (in `.generated_clients/<namespace>/`): Lustre SPA entry, WebSocket transport, tree-shaken page modules, codec, effect shim.

The client package is a standalone Gleam project. The server project is the input to codegen.

## Examples

- [`examples/realworld/`](https://github.com/pairshaped/rally-gleam/tree/master/examples/realworld): Conduit clone with auth, articles, comments, tags, favorites, follows. Uses both RPC and stateful server models.

## More docs

- [Pages](https://github.com/pairshaped/rally-gleam/blob/master/pages/guides/pages.md): routing, page lifecycle, SSR loading, and layouts
- [Server messaging](https://github.com/pairshaped/rally-gleam/blob/master/pages/guides/server-messaging.md): RPC, stateful server pages, and broadcast
- [Runtime](https://github.com/pairshaped/rally-gleam/blob/master/pages/guides/runtime.md): the `rally_runtime/*` modules app code imports
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

Rally depends on [Libero](https://hexdocs.pm/libero/). App projects should add both packages with `gleam add rally libero`.

## Influences

- [Lamdera](https://lamdera.com): explicit server handler types as the contract, TEA on both sides
- [Lustre](https://lustre.build/): TEA, effects, and the client-side UI runtime
- [elm-land](https://elm.land): file-based routing conventions
- [Libero](https://hexdocs.pm/libero/): wire protocol and RPC contract layer
- [Marmot](https://hexdocs.pm/marmot/): SQL-first codegen with live SQLite introspection

## License

MIT. See [LICENSE](https://github.com/pairshaped/rally-gleam/blob/master/LICENSE).
