import gleam/result
import rally/runtime/migrate
import sqlight

@external(erlang, "rally_runtime_test_db_ffi", "clone_db")
fn clone_db(_template: sqlight.Connection) -> Result(sqlight.Connection, Nil) {
  Error(Nil)
}

@external(erlang, "rally_runtime_test_db_ffi", "pt_put")
fn pt_put(_key: String, _value: Result(sqlight.Connection, Nil)) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_test_db_ffi", "pt_get")
fn pt_get(
  _key: String,
  _default: Result(sqlight.Connection, Nil),
) -> Result(sqlight.Connection, Nil) {
  Error(Nil)
}

fn template_db(migrations_dir: String) -> Result(sqlight.Connection, Nil) {
  let cache_key = "rally_test_template:" <> migrations_dir
  case pt_get(cache_key, Error(Nil)) {
    Ok(conn) -> Ok(conn)
    Error(Nil) -> {
      use conn <- result.try(case sqlight.open(":memory:") {
        Ok(conn) -> Ok(conn)
        _ -> Error(Nil)
      })
      use _ <- result.try(case migrate.run(conn:, dir: migrations_dir) {
        Ok(_) -> Ok(Nil)
        _ -> Error(Nil)
      })
      pt_put(cache_key, Ok(conn))
      Ok(conn)
    }
  }
}

/// Open a fresh in-memory database with migrations already applied.
/// The first call runs migrations into a template db cached via
/// persistent_term. Subsequent calls clone it via SQLite's backup
/// API (page-level copy), avoiding re-running migrations per test.
pub fn setup(migrations_dir: String) -> Result(sqlight.Connection, Nil) {
  use conn <- result.try(template_db(migrations_dir))
  clone_db(conn)
}
