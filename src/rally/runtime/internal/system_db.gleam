//// Internal system database helpers for logging and shared connection state.

import gleam/dynamic/decode
import gleam/result
import gleam/time/timestamp
import sqlight

// synchronous=OFF is safe here: this is observability data, not app state.
// Losing a few recent messages on crash is acceptable for the throughput gain.
pub fn open(path: String) -> Result(sqlight.Connection, sqlight.Error) {
  use conn <- result.try(sqlight.open(path))
  use _ <- result.try(sqlight.exec("PRAGMA journal_mode=WAL;", on: conn))
  use _ <- result.try(sqlight.exec("PRAGMA synchronous=OFF;", on: conn))
  use _ <- result.try(sqlight.exec("PRAGMA busy_timeout=5000;", on: conn))
  use _ <- result.try(sqlight.exec(
    "CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY,
  timestamp INTEGER NOT NULL,
  session_id TEXT NOT NULL,
  user_id INTEGER,
  page TEXT NOT NULL,
  direction TEXT NOT NULL,
  variant TEXT NOT NULL,
  payload BLOB,
  elapsed_ms INTEGER
);
CREATE TABLE IF NOT EXISTS jobs (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  payload BLOB NOT NULL,
  run_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  last_error TEXT,
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  claimed_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_page ON messages(page);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_status_run_at ON jobs(status, run_at);",
    on: conn,
  ))
  use _ <- result.try(ensure_column(
    conn: conn,
    table: "jobs",
    column: "claimed_at",
    ddl: "ALTER TABLE jobs ADD COLUMN claimed_at INTEGER;",
  ))
  Ok(conn)
}

fn ensure_column(
  conn conn: sqlight.Connection,
  table table: String,
  column column: String,
  ddl ddl: String,
) -> Result(Nil, sqlight.Error) {
  case
    sqlight.query(
      "SELECT name FROM pragma_table_info(?1) WHERE name = ?2",
      on: conn,
      with: [sqlight.text(table), sqlight.text(column)],
      expecting: {
        use name <- decode.field(0, decode.string)
        decode.success(name)
      },
    )
  {
    Ok([_]) -> Ok(Nil)
    Ok(_) -> sqlight.exec(ddl, on: conn)
    Error(e) -> Error(e)
  }
}

pub fn log_to_server(
  db db: sqlight.Connection,
  session_id session_id: String,
  user_id user_id: Result(Int, Nil),
  page page: String,
  variant_name variant_name: String,
  raw_payload raw_payload: BitArray,
  elapsed_ms elapsed_ms: Int,
) -> Nil {
  let now = unix_seconds()
  let _query_result =
    sqlight.query(
      "INSERT INTO messages (timestamp, session_id, user_id, page, direction, variant, payload, elapsed_ms)
       VALUES (?1, ?2, ?3, ?4, 'to_server', ?5, ?6, ?7)",
      on: db,
      with: [
        sqlight.int(now),
        sqlight.text(session_id),
        nullable_int(user_id),
        sqlight.text(page),
        sqlight.text(variant_name),
        sqlight.blob(raw_payload),
        sqlight.int(elapsed_ms),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn log_to_client(
  db db: sqlight.Connection,
  session_id session_id: String,
  user_id user_id: Result(Int, Nil),
  page page: String,
  variant variant: String,
  elapsed_ms elapsed_ms: Int,
) -> Nil {
  let now = unix_seconds()
  let _query_result =
    sqlight.query(
      "INSERT INTO messages (timestamp, session_id, user_id, page, direction, variant, elapsed_ms)
       VALUES (?1, ?2, ?3, ?4, 'to_client', ?5, ?6)",
      on: db,
      with: [
        sqlight.int(now),
        sqlight.text(session_id),
        nullable_int(user_id),
        sqlight.text(page),
        sqlight.text(variant),
        sqlight.int(elapsed_ms),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn log_broadcast(
  db db: sqlight.Connection,
  page page: String,
  variant variant: String,
) -> Nil {
  let now = unix_seconds()
  let _query_result =
    sqlight.query(
      "INSERT INTO messages (timestamp, session_id, user_id, page, direction, variant)
       VALUES (?1, '', NULL, ?2, 'broadcast', ?3)",
      on: db,
      with: [
        sqlight.int(now),
        sqlight.text(page),
        sqlight.text(variant),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

fn nullable_int(val: Result(Int, Nil)) -> sqlight.Value {
  case val {
    Ok(n) -> sqlight.int(n)
    _ -> sqlight.null()
  }
}

fn unix_seconds() -> Int {
  let #(seconds, _nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time())
  seconds
}

pub fn store_conn(conn: sqlight.Connection) -> Nil {
  store_system_conn(conn)
}

@external(erlang, "rally_runtime_ffi", "store_system_conn")
fn store_system_conn(_conn: sqlight.Connection) -> Nil {
  Nil
}

pub fn get_conn() -> Result(sqlight.Connection, Nil) {
  get_system_conn_ffi()
}

@external(erlang, "rally_runtime_ffi", "get_system_conn")
fn get_system_conn_ffi() -> Result(sqlight.Connection, Nil) {
  Error(Nil)
}

pub fn message_count(db: sqlight.Connection) -> Int {
  case
    sqlight.query(
      "SELECT COUNT(*) FROM messages",
      on: db,
      with: [],
      expecting: { decode.at([0], decode.int) },
    )
  {
    Ok([count]) -> count
    _ -> 0
  }
}
