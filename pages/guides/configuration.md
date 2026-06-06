# Configuration

Rally uses normal project config plus Proute config. The Rally Scoreboard example is the reference shape: authored pages live under `src/<mount>/pages/`, Proute owns routing, Rally owns SSR and browser lifecycle glue, and Libero owns the wire codecs for page-local load/save contracts.

## gleam.toml

Use `[tools.rally.context]` to name the server-side value Rally passes to page `load` and `handle_save` functions. The starter app uses `sqlight.Connection`.

```toml
[tools.rally.context]
module = "sqlight"
type = "Connection"

[tools.marmot]
database = "db/dev.sqlite"
sql_dir = "src/sql"
output = "src/generated/sql"
```

When `[tools.marmot]` is present, `rally migrate` delegates to `marmot migrate`; Rally has no migration runner of its own. `rally build` runs Marmot before Rally codegen. Marmot's default migration directory is `db/migrations`.

Rally checks delegated tools before running them. If `[tools.marmot]` is present, the app must list `marmot`. Rally codegen uses Libero for wire codecs, so the app must list `libero`. These can be in `[dependencies]`, `[dev-dependencies]`, or `[dev_dependencies]`. Proute is a Rally dependency; apps configure routes with `proute.toml` but do not need to list `proute` directly.

## proute.toml

Proute config defines mounts and route roots.

```toml
[proute]
pages_root = "src"

[[proute.mounts]]
name = "public"
route_root = "/"
```

Page modules for that mount live under `src/public/pages/`. Proute generates route params, query params, page enums, path helpers, and page dispatch under `src/generated/proute/**`.

## Build Outputs

`gleam run -m rally build` runs Marmot if configured, runs Proute when `proute.toml` exists, generates Rally/Libero glue, then builds the app for Erlang and JavaScript.

Generated files stay in the app package:

| Path | Purpose |
| --- | --- |
| `src/generated/proute/**` | Route types, route params, query params, path helpers, and page dispatch |
| `src/generated/rally/**` | Browser boot, SSR, hydration, transport, WebSocket, topic, and load/save glue |
| `src/generated/libero/**` | ETF codec helpers, decoder registration, wire helpers, and contract metadata |
| `src/generated/sql/**` | Marmot query functions when SQL codegen is configured |

Do not edit generated files directly. Change pages, config, SQL, or migrations, then run `rally build` again.

## Runtime Environment

Rally checks the `APP_ENV` environment variable at startup.

- `APP_ENV=dev` is the default. Session cookies are set without the `Secure` flag so `localhost` works, and console output is verbose.
- `APP_ENV=prod` enables secure session cookies and quieter logging. Set this in production.

```sh
APP_ENV=prod gleam run
```
