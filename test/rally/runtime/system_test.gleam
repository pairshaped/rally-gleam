import gleam/dynamic/decode
import gleam/erlang/process
import gleeunit/should
import rally/runtime/internal/system_db as system
import rally/runtime/system as runtime_system
import sqlight

@external(erlang, "rally_runtime_test_db_ffi", "connection_usable")
fn connection_usable(_conn: sqlight.Connection) -> Bool {
  False
}

pub fn open_creates_observability_tables_test() {
  let assert Ok(conn) = system.open(":memory:")

  table_exists(conn, "messages") |> should.equal(True)
  table_exists(conn, "jobs") |> should.equal(True)
}

pub fn supervised_job_runner_returns_startable_child_spec_test() {
  let child =
    runtime_system.supervised_job_runner(path: ":memory:", handler: fn(_, _) {
      Ok(Nil)
    })

  let assert Ok(started) = child.start()
  process.unlink(started.pid)
  process.kill(started.pid)
}

pub fn start_replaces_and_closes_previous_global_connection_test() {
  runtime_system.start(":memory:")
  let assert Ok(first_conn) = system.get_conn()

  runtime_system.start(":memory:")
  let assert Ok(second_conn) = system.get_conn()

  connection_usable(first_conn) |> should.be_false()
  connection_usable(second_conn) |> should.be_true()
}

pub fn log_to_client_persists_message_test() {
  let assert Ok(conn) = system.open(":memory:")

  system.log_to_client(
    db: conn,
    session_id: "session-1",
    user_id: Ok(42),
    page: "/home",
    variant: "GotThing",
    elapsed_ms: 12,
  )

  messages(conn)
  |> should.equal([#("session-1", 42, "/home", "to_client", "GotThing", 12)])
}

pub fn log_broadcast_persists_message_test() {
  let assert Ok(conn) = system.open(":memory:")

  system.log_broadcast(db: conn, page: "/room", variant: "RoomUpdated")

  broadcast_messages(conn)
  |> should.equal([#("", "/room", "broadcast", "RoomUpdated")])
}

fn table_exists(conn: sqlight.Connection, name: String) -> Bool {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?1",
      on: conn,
      with: [sqlight.text(name)],
      expecting: {
        use table_name <- decode.field(0, decode.string)
        decode.success(table_name)
      },
    )
  case rows {
    [_] -> True
    _ -> False
  }
}

fn messages(
  conn: sqlight.Connection,
) -> List(#(String, Int, String, String, String, Int)) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT session_id, user_id, page, direction, variant, elapsed_ms FROM messages",
      on: conn,
      with: [],
      expecting: {
        use session_id <- decode.field(0, decode.string)
        use user_id <- decode.field(1, decode.int)
        use page <- decode.field(2, decode.string)
        use direction <- decode.field(3, decode.string)
        use variant <- decode.field(4, decode.string)
        use elapsed_ms <- decode.field(5, decode.int)
        decode.success(#(
          session_id,
          user_id,
          page,
          direction,
          variant,
          elapsed_ms,
        ))
      },
    )
  rows
}

fn broadcast_messages(
  conn: sqlight.Connection,
) -> List(#(String, String, String, String)) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT session_id, page, direction, variant FROM messages",
      on: conn,
      with: [],
      expecting: {
        use session_id <- decode.field(0, decode.string)
        use page <- decode.field(1, decode.string)
        use direction <- decode.field(2, decode.string)
        use variant <- decode.field(3, decode.string)
        decode.success(#(session_id, page, direction, variant))
      },
    )
  rows
}

pub fn open_creates_jobs_claimed_at_column_test() {
  let assert Ok(conn) = system.open(":memory:")

  column_exists(conn, "jobs", "claimed_at") |> should.equal(True)
}

fn column_exists(
  conn: sqlight.Connection,
  table: String,
  column: String,
) -> Bool {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT name FROM pragma_table_info(?1) WHERE name = ?2",
      on: conn,
      with: [sqlight.text(table), sqlight.text(column)],
      expecting: {
        use name <- decode.field(0, decode.string)
        decode.success(name)
      },
    )
  case rows {
    [_] -> True
    _ -> False
  }
}
