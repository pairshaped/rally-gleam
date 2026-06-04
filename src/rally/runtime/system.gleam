//// System database: observability and background jobs.
////
//// Opens a separate SQLite database (system.db) for message logging and
//// the job queue. The connection is stored globally so any WS handler
//// process can log messages. Uses synchronous=OFF because losing a few
//// recent log entries on crash is acceptable for the throughput gain.

import gleam/int
import gleam/otp/actor
import gleam/otp/supervision
import logging
import rally/runtime/internal/system_db
import rally/runtime/jobs
import sqlight

pub type JobHandler =
  fn(String, BitArray) -> Result(Nil, String)

/// Call during app startup. Opens the system DB and stores the connection
/// globally so any process (WS handlers) can access it.
pub fn start(path: String) -> Nil {
  case open_and_store(path) {
    Ok(_) -> Nil
    Error(err) -> {
      logging.log(logging.Warning, "Failed to open system DB: " <> err.message)
      Nil
    }
  }
}

/// Start the system DB with an unsupervised background job runner.
pub fn start_with_jobs(path path: String, handler handler: JobHandler) -> Nil {
  case start_job_runner(path: path, handler: handler) {
    Ok(_) -> logging.log(logging.Info, "Job runner started")
    Error(err) ->
      logging.log(
        logging.Warning,
        "Failed to start job runner: " <> start_error_to_string(err),
      )
  }
}

/// Start the system DB and job runner, returning the actor handle.
pub fn start_job_runner(
  path path: String,
  handler handler: JobHandler,
) -> actor.StartResult(Nil) {
  case open_and_store(path) {
    Ok(conn) -> jobs.start_runner(db: conn, handler: handler)
    Error(err) -> Error(actor.InitFailed(err.message))
  }
}

/// Return a worker child specification for supervising the job runner.
pub fn supervised_job_runner(
  path path: String,
  handler handler: JobHandler,
) -> supervision.ChildSpecification(Nil) {
  supervision.worker(fn() { start_job_runner(path: path, handler: handler) })
}

/// Enqueue a job to run at a specific time.
pub fn enqueue(
  name name: String,
  payload payload: BitArray,
  run_at run_at: Int,
) -> Nil {
  case system_db.get_conn() {
    Ok(conn) ->
      jobs.enqueue(db: conn, name: name, payload: payload, run_at: run_at)
    _ -> Nil
  }
}

/// Enqueue a job to run after a delay.
pub fn enqueue_in(
  name name: String,
  payload payload: BitArray,
  delay_seconds delay_seconds: Int,
) -> Nil {
  case system_db.get_conn() {
    Ok(conn) ->
      jobs.enqueue_in(
        db: conn,
        name: name,
        payload: payload,
        delay_seconds: delay_seconds,
      )
    _ -> Nil
  }
}

/// Enqueue a job to run immediately.
pub fn enqueue_now(name name: String, payload payload: BitArray) -> Nil {
  case system_db.get_conn() {
    Ok(conn) -> jobs.enqueue(db: conn, name: name, payload: payload, run_at: 0)
    _ -> Nil
  }
}

fn open_and_store(path: String) -> Result(sqlight.Connection, sqlight.Error) {
  case system_db.open(path) {
    Ok(conn) -> {
      let previous_conn = system_db.get_conn()
      system_db.store_conn(conn)
      close_previous_conn(previous_conn)
      logging.log(logging.Info, "System DB opened: " <> path)
      let count = system_db.message_count(conn)
      logging.log(
        logging.Info,
        "System: " <> int.to_string(count) <> " messages recorded",
      )
      Ok(conn)
    }
    Error(err) -> Error(err)
  }
}

fn close_previous_conn(conn: Result(sqlight.Connection, Nil)) -> Nil {
  case conn {
    Ok(conn) -> {
      case sqlight.close(conn) {
        Ok(Nil) -> Nil
        Error(err) ->
          logging.log(
            logging.Warning,
            "Failed to close previous system DB connection: " <> err.message,
          )
      }
    }
    Error(Nil) -> Nil
  }
}

fn start_error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "initialization timed out"
    actor.InitFailed(reason) -> reason
    actor.InitExited(_) -> "process exited during initialization"
  }
}
