//// Durable background job runner backed by SQLite.
////
//// Jobs are rows in the system DB's `jobs` table. A poller actor claims
//// ready jobs with UPDATE...RETURNING, runs the handler, and marks them
//// completed or schedules a retry. Failed jobs get quadratic backoff
//// (5s, 20s, 45s, 80s) and are dead-lettered after max_attempts.
//// Running jobs have a claimed_at lease so they can be reclaimed if the
//// process crashes. Use run_once for deterministic testing without the
//// polling actor.

import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/otp/actor
import gleam/time/timestamp
import logging
import sqlight

/// How often the polling actor checks for ready jobs (milliseconds).
const poll_interval_ms = 1000

/// Jobs that fail this many times are marked dead and stop retrying.
const max_attempts = 5

pub type JobHandler =
  fn(String, BitArray) -> Result(Nil, String)

pub type Job {
  Job(id: Int, name: String, payload: BitArray, attempts: Int)
}

type Msg {
  Poll
}

type State {
  State(db: sqlight.Connection, handler: JobHandler, self: Subject(Msg))
}

pub fn enqueue(
  db db: sqlight.Connection,
  name name: String,
  payload payload: BitArray,
  run_at run_at: Int,
) -> Nil {
  let _query_result =
    sqlight.query(
      "INSERT INTO jobs (name, payload, run_at, attempts, status) VALUES (?1, ?2, ?3, 0, 'pending')",
      on: db,
      with: [sqlight.text(name), sqlight.blob(payload), sqlight.int(run_at)],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn enqueue_in(
  db db: sqlight.Connection,
  name name: String,
  payload payload: BitArray,
  delay_seconds delay_seconds: Int,
) -> Nil {
  let run_at = unix_seconds() + delay_seconds
  enqueue(db: db, name: name, payload: payload, run_at: run_at)
}

pub fn start_runner(
  db db: sqlight.Connection,
  handler handler: JobHandler,
) -> Result(actor.Started(Nil), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    let selector =
      process.new_selector()
      |> process.select_map(subject, fn(msg) { msg })
    let state = State(db:, handler:, self: subject)
    process.send(subject, Poll)
    actor.initialised(state)
    |> actor.selecting(selector)
    |> Ok
  })
  |> actor.on_message(fn(state, msg) {
    let Poll = msg
    process_pending_jobs_at(
      db: state.db,
      handler: state.handler,
      now: unix_seconds(),
    )
    let _timer = process.send_after(state.self, poll_interval_ms, Poll)
    actor.continue(state)
  })
  |> actor.start
}

/// Jobs claimed longer than this are assumed crashed and reclaimed.
const running_lease_seconds = 60

pub fn run_once(db db: sqlight.Connection, handler handler: JobHandler) -> Nil {
  process_pending_jobs_at(db: db, handler: handler, now: unix_seconds())
}

pub fn run_once_at(
  db db: sqlight.Connection,
  now now: Int,
  handler handler: JobHandler,
) -> Nil {
  process_pending_jobs_at(db: db, handler: handler, now: now)
}

fn process_pending_jobs_at(
  db db: sqlight.Connection,
  handler handler: JobHandler,
  now now: Int,
) -> Nil {
  case fetch_ready_jobs(db, now) {
    [] -> Nil
    jobs -> run_jobs(db: db, handler: handler, jobs: jobs)
  }
}

fn fetch_ready_jobs(db: sqlight.Connection, now: Int) -> List(Job) {
  let stale_before = now - running_lease_seconds
  case
    sqlight.query(
      "UPDATE jobs
       SET status = 'running', claimed_at = ?1
       WHERE id IN (
         SELECT id FROM jobs
         WHERE run_at <= ?1
         AND (
           status = 'pending'
           OR (status = 'running' AND (claimed_at IS NULL OR claimed_at <= ?2))
         )
         ORDER BY run_at
         LIMIT 10
       )
       RETURNING id, name, payload, attempts",
      on: db,
      with: [sqlight.int(now), sqlight.int(stale_before)],
      expecting: {
        use id <- decode.field(0, decode.int)
        use name <- decode.field(1, decode.string)
        use payload <- decode.field(2, decode.bit_array)
        use attempts <- decode.field(3, decode.int)
        decode.success(Job(id:, name:, payload:, attempts:))
      },
    )
  {
    Ok(jobs) -> jobs
    _ -> []
  }
}

fn run_jobs(
  db db: sqlight.Connection,
  handler handler: JobHandler,
  jobs jobs: List(Job),
) -> Nil {
  case jobs {
    [] -> Nil
    [job, ..rest] -> {
      run_single_job(db: db, handler: handler, job: job)
      run_jobs(db: db, handler: handler, jobs: rest)
    }
  }
}

fn run_single_job(
  db db: sqlight.Connection,
  handler handler: JobHandler,
  job job: Job,
) -> Nil {
  case handler(job.name, job.payload) {
    Ok(_) -> mark_completed(db, job.id)
    Error(reason) -> {
      let next_attempts = job.attempts + 1
      case next_attempts >= max_attempts {
        True -> {
          mark_dead(db: db, job_id: job.id, reason: reason)
          logging.log(
            logging.Warning,
            "Job "
              <> job.name
              <> " dead-lettered after "
              <> int.to_string(max_attempts)
              <> " attempts: "
              <> reason,
          )
        }
        False -> {
          // Quadratic backoff: 5s, 20s, 45s, 80s. Spreads retries without
          // requiring jitter since jobs are single-writer (one poller).
          let backoff_seconds = next_attempts * next_attempts * 5
          let retry_at = unix_seconds() + backoff_seconds
          mark_retry(
            db: db,
            job_id: job.id,
            attempts: next_attempts,
            retry_at: retry_at,
            reason: reason,
          )
        }
      }
    }
  }
}

fn mark_completed(db: sqlight.Connection, job_id: Int) -> Nil {
  let _result =
    sqlight.query(
      "UPDATE jobs SET status = 'completed' WHERE id = ?1",
      on: db,
      with: [sqlight.int(job_id)],
      expecting: decode.success(Nil),
    )
  Nil
}

fn mark_dead(
  db db: sqlight.Connection,
  job_id job_id: Int,
  reason reason: String,
) -> Nil {
  let _result =
    sqlight.query(
      "UPDATE jobs SET status = 'dead', last_error = ?2 WHERE id = ?1",
      on: db,
      with: [sqlight.int(job_id), sqlight.text(reason)],
      expecting: decode.success(Nil),
    )
  Nil
}

fn mark_retry(
  db db: sqlight.Connection,
  job_id job_id: Int,
  attempts attempts: Int,
  retry_at retry_at: Int,
  reason reason: String,
) -> Nil {
  let _result =
    sqlight.query(
      "UPDATE jobs SET status = 'pending', attempts = ?2, run_at = ?3, last_error = ?4, claimed_at = NULL WHERE id = ?1",
      on: db,
      with: [
        sqlight.int(job_id),
        sqlight.int(attempts),
        sqlight.int(retry_at),
        sqlight.text(reason),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

fn unix_seconds() -> Int {
  let #(seconds, _nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time())
  seconds
}
