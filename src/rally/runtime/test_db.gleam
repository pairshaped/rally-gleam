import gleam/result
import gleam/string
import marmot
import simplifile
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
      let db_path = template_db_path(migrations_dir)
      let _ =
        simplifile.delete_all(paths: [
          db_path,
          db_path <> "-wal",
          db_path <> "-shm",
          db_path <> "-journal",
        ])
      use _ <- result.try(case marmot.migrate_from(db_path, migrations_dir) {
        Ok(_) -> Ok(Nil)
        _ -> Error(Nil)
      })
      use conn <- result.try(case sqlight.open(db_path) {
        Ok(conn) -> Ok(conn)
        _ -> Error(Nil)
      })
      pt_put(cache_key, Ok(conn))
      Ok(conn)
    }
  }
}

fn template_db_path(migrations_dir: String) -> String {
  "/tmp/rally_test_template_"
  <> string.replace(migrations_dir, "/", "_")
  <> ".db"
}

/// Open a fresh in-memory database with migrations already applied.
/// The first call delegates migrations to Marmot and caches the resulting
/// template db via persistent_term. Subsequent calls clone it via SQLite's backup
/// API (page-level copy), avoiding re-running migrations per test.
pub fn setup(migrations_dir: String) -> Result(sqlight.Connection, Nil) {
  use conn <- result.try(template_db(migrations_dir))
  clone_db(conn)
}
