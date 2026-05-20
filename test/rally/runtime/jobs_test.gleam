import gleam/dynamic/decode
import gleeunit/should
import rally/runtime/internal/system_db as system
import rally/runtime/jobs
import sqlight

pub fn run_once_completes_ready_jobs_test() {
  let assert Ok(conn) = system.open(":memory:")
  jobs.enqueue(
    db: conn,
    name: "welcome",
    payload: <<"payload":utf8>>,
    run_at: 0,
  )

  jobs.run_once(db: conn, handler: fn(name, payload) {
    name |> should.equal("welcome")
    payload |> should.equal(<<"payload":utf8>>)
    Ok(Nil)
  })

  job_statuses(conn)
  |> should.equal(["completed"])
}

pub fn run_once_retries_failed_jobs_with_backoff_test() {
  let assert Ok(conn) = system.open(":memory:")
  jobs.enqueue(db: conn, name: "retry_me", payload: <<>>, run_at: 0)

  jobs.run_once(db: conn, handler: fn(_, _) { Error("nope") })

  let assert [row] = job_attempts(conn)
  row.status |> should.equal("pending")
  row.attempts |> should.equal(1)
  row.last_error |> should.equal("nope")
  should.equal(row.run_at > 0, True)
}

pub fn run_once_reclaims_running_jobs_test() {
  let assert Ok(conn) = system.open(":memory:")
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO jobs (name, payload, run_at, attempts, status) VALUES (?1, ?2, ?3, 0, 'running')",
      on: conn,
      with: [
        sqlight.text("orphan"),
        sqlight.blob(<<"payload":utf8>>),
        sqlight.int(0),
      ],
      expecting: decode.success(Nil),
    )

  jobs.run_once(db: conn, handler: fn(name, payload) {
    name |> should.equal("orphan")
    payload |> should.equal(<<"payload":utf8>>)
    Ok(Nil)
  })

  job_statuses(conn)
  |> should.equal(["completed"])
}

type JobAttempt {
  JobAttempt(status: String, attempts: Int, run_at: Int, last_error: String)
}

fn job_statuses(conn: sqlight.Connection) -> List(String) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT status FROM jobs ORDER BY id",
      on: conn,
      with: [],
      expecting: {
        use status <- decode.field(0, decode.string)
        decode.success(status)
      },
    )
  rows
}

pub fn run_once_does_not_reclaim_fresh_running_job_test() {
  let assert Ok(conn) = system.open(":memory:")
  let now = 1_700_000_000
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO jobs (name, payload, run_at, attempts, status, claimed_at) VALUES (?1, ?2, ?3, 0, 'running', ?4)",
      on: conn,
      with: [
        sqlight.text("fresh"),
        sqlight.blob(<<"payload":utf8>>),
        sqlight.int(0),
        sqlight.int(now),
      ],
      expecting: decode.success(Nil),
    )

  jobs.run_once_at(db: conn, now: now + 10, handler: fn(_, _) {
    should.fail()
    Ok(Nil)
  })

  job_statuses(conn) |> should.equal(["running"])
}

pub fn run_once_reclaims_stale_running_job_test() {
  let assert Ok(conn) = system.open(":memory:")
  let now = 1_700_000_000
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO jobs (name, payload, run_at, attempts, status, claimed_at) VALUES (?1, ?2, ?3, 0, 'running', ?4)",
      on: conn,
      with: [
        sqlight.text("stale"),
        sqlight.blob(<<"payload":utf8>>),
        sqlight.int(0),
        sqlight.int(now - 120),
      ],
      expecting: decode.success(Nil),
    )

  jobs.run_once_at(db: conn, now: now, handler: fn(name, _) {
    name |> should.equal("stale")
    Ok(Nil)
  })

  job_statuses(conn) |> should.equal(["completed"])
}

fn job_attempts(conn: sqlight.Connection) -> List(JobAttempt) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT status, attempts, run_at, last_error FROM jobs ORDER BY id",
      on: conn,
      with: [],
      expecting: {
        use status <- decode.field(0, decode.string)
        use attempts <- decode.field(1, decode.int)
        use run_at <- decode.field(2, decode.int)
        use last_error <- decode.field(3, decode.string)
        decode.success(JobAttempt(status:, attempts:, run_at:, last_error:))
      },
    )
  rows
}
