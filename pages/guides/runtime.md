# Runtime modules

Most Rally apps import only a few `rally/runtime/*` modules directly. Generated code uses more of them behind the scenes.

| Module | Use it for |
| --- | --- |
| `rally/runtime/effect` | Page effects for navigation and broadcasts |
| `rally/runtime/db` | SQLite open, timed query wrapper, nested transactions, SQL value helpers |
| `rally/runtime/system` | App startup and background jobs |
| `rally/runtime/session` | Session IDs and session cookie headers |
| `rally/runtime/auth` | Auth policy and load result types used by page modules |
| `rally/runtime/env` | `APP_ENV` parsing and production cookie policy |
| `rally/runtime/test_db` | In-memory SQLite setup for tests |

## `effect`

Generated Rally browser functions are the primary way pages talk to the server. They send a typed page-local request and deliver the response back to your update function.

Broadcast effects are for page handlers that need to push a message to more than one connection. Call them from your server-side handler when something changes that multiple clients care about.

`effect.navigate` pushes a URL on the client side without a full page load. For arbitrary Lustre effects, import `lustre/effect` directly.

## `db`

`db.open` creates a SQLite connection at startup. It configures WAL mode, sets a busy timeout, and enables foreign keys.

`db.query` wraps your SQL calls with timing logs so slow queries show up in your system message log. `db.transaction` uses SAVEPOINTs, which means transactions can nest safely.

`db.one` returns the single row from a result set, or `None` if the set is empty. For encoding values into SQL parameters, `db.bool_to_int` and `db.nullable_text` handle the common cases.

## `system`

`system.start` runs during app startup to initialize the system database. The system DB stores message logs and the job queue.

When your app has background jobs and no OTP supervision tree, use `system.start_with_jobs`. It starts the job runner alongside the system DB, but the runner is not supervised.

If your app has a supervisor, use `system.supervised_job_runner` and add the returned child specification to your tree. `system.start_job_runner` is the direct start function behind that child specification.

## `session`

`session` handles generation and extraction of session cookies. It creates cryptographically random session IDs and produces the `Set-Cookie` header with the right flags for your environment. Auth flows depend on it to associate requests with sessions, and SSR uses it to identify the connection before the WebSocket upgrades.

## `auth`

Rally's auth system is convention-based: it activates when a file at `src/<namespace>/auth.gleam` exists in your project. The `auth` module defines policy types (`Required` and `Optional`) that page modules reference to declare whether a visitor must be authenticated. `LoadResult` carries the auth outcome into SSR so pages can render differently for logged-in and anonymous users. Your identity type threads through the whole pipeline, from the auth check to the page's model.

## `env`

The `env` module parses the `APP_ENV` environment variable to determine which environment the app is running in. In production, session cookies get the `Secure` flag and browser console logging stays off. During development these restrictions are relaxed so you can work over plain HTTP and see client-side log output.

## `test_db`

`test_db` gives you an in-memory SQLite database for tests. It applies your migrations the first time, then caches the schema so repeated test setups skip the migration step.
