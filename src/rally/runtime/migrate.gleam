//// SQL migration runner for SQLite. Reads numbered .sql files from a
//// directory, tracks the last applied version in a schema_migrations
//// table, and runs pending migrations inside transactions. Failed
//// migrations roll back and leave the version at the last success.

import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile
import sqlight

pub type MigrationError {
  TableCreateFailed(message: String)
  VersionQueryFailed(message: String)
  VersionInitFailed(message: String)
  DirReadFailed(message: String)
  FileReadFailed(filename: String, message: String)
  MigrationFailed(filename: String, message: String)
  VersionUpdateFailed(message: String)
  FilenameParseFailed(filename: String)
  SchemaTableCorrupted(row_count: Int)
}

pub fn error_to_string(error: MigrationError) -> String {
  case error {
    TableCreateFailed(message:) ->
      "Failed to create schema_migrations: " <> message
    VersionQueryFailed(message:) ->
      "Failed to get migration version: " <> message
    VersionInitFailed(message:) ->
      "Failed to init schema_migrations: " <> message
    DirReadFailed(message:) ->
      "Failed to read migrations directory: " <> message
    FileReadFailed(filename:, message:) ->
      "Failed to read " <> filename <> ": " <> message
    MigrationFailed(filename:, message:) ->
      "Migration " <> filename <> " failed: " <> message
    VersionUpdateFailed(message:) ->
      "Failed to update migration version: " <> message
    FilenameParseFailed(filename:) ->
      "Invalid migration filename (expected NNN_name.sql): " <> filename
    SchemaTableCorrupted(row_count:) ->
      "schema_migrations table has "
      <> int.to_string(row_count)
      <> " rows (expected 0 or 1). Inspect the table and resolve manually; "
      <> "Rally will not silently reset to version 0."
  }
}

pub fn run(
  conn conn: sqlight.Connection,
  dir dir: String,
) -> Result(Nil, MigrationError) {
  use _ <- result.try(
    sqlight.exec(
      "CREATE TABLE IF NOT EXISTS schema_migrations (
        last_migration INTEGER NOT NULL
      );",
      on: conn,
    )
    |> result.map_error(fn(e) { TableCreateFailed(message: e.message) }),
  )

  use current <- result.try(get_current_version(conn))

  use files <- result.try(
    simplifile.read_directory(at: dir)
    |> result.map_error(fn(e) {
      DirReadFailed(message: simplifile.describe_error(e))
    }),
  )

  use migrations <- result.try(
    files
    |> list.filter(fn(f) { string.ends_with(f, ".sql") })
    |> list.sort(string.compare)
    |> list.try_map(fn(file) {
      use number <- result.try(parse_number(file))
      Ok(#(number, file))
    }),
  )

  let pending =
    migrations
    |> list.filter(fn(f) {
      let #(number, _) = f
      number > current
    })

  case pending {
    [] -> {
      io.println("  migrations: up to date (v" <> int.to_string(current) <> ")")
      Ok(Nil)
    }
    _ -> run_pending(conn: conn, dir: dir, files: pending)
  }
}

fn get_current_version(
  conn: sqlight.Connection,
) -> Result(Int, MigrationError) {
  let decoder = {
    use version <- decode.field(0, decode.int)
    decode.success(version)
  }

  case
    sqlight.query(
      "SELECT last_migration FROM schema_migrations",
      on: conn,
      with: [],
      expecting: decoder,
    )
  {
    Ok([version]) -> Ok(version)
    Ok([]) -> {
      sqlight.exec(
        "INSERT INTO schema_migrations (last_migration) VALUES (0);",
        on: conn,
      )
      |> result.map_error(fn(e) { VersionInitFailed(message: e.message) })
      |> result.map(fn(_) { 0 })
    }
    Ok(rows) -> Error(SchemaTableCorrupted(row_count: list.length(rows)))
    Error(e) -> Error(VersionQueryFailed(message: e.message))
  }
}

fn run_pending(
  conn conn: sqlight.Connection,
  dir dir: String,
  files files: List(#(Int, String)),
) -> Result(Nil, MigrationError) {
  case files {
    [] -> Ok(Nil)
    [#(num, file), ..rest] -> {
      let path = dir <> "/" <> file

      use sql <- result.try(
        simplifile.read(path)
        |> result.map_error(fn(e) {
          FileReadFailed(filename: file, message: simplifile.describe_error(e))
        }),
      )

      io.println("  migration " <> int.to_string(num) <> ": " <> file)

      use _ <- result.try(
        sqlight.exec("BEGIN", on: conn)
        |> result.map_error(fn(e) {
          MigrationFailed(filename: file, message: e.message)
        }),
      )

      use _ <- result.try(run_migration_sql(
        conn: conn,
        num: num,
        file: file,
        sql: sql,
      ))
      run_pending(conn: conn, dir: dir, files: rest)
    }
  }
}

fn run_migration_sql(
  conn conn: sqlight.Connection,
  num num: Int,
  file file: String,
  sql sql: String,
) -> Result(Nil, MigrationError) {
  case sqlight.exec(sql, on: conn) {
    Ok(_) -> {
      case
        sqlight.exec(
          "UPDATE schema_migrations SET last_migration = "
            <> int.to_string(num)
            <> ";",
          on: conn,
        )
      {
        Ok(_) -> {
          case sqlight.exec("COMMIT", on: conn) {
            Ok(_) -> Ok(Nil)
            Error(e) -> {
              Error(VersionUpdateFailed(message: e.message))
            }
          }
        }
        Error(e) -> {
          let _rollback = sqlight.exec("ROLLBACK", on: conn)
          Error(VersionUpdateFailed(message: e.message))
        }
      }
    }
    Error(e) -> {
      let _rollback = sqlight.exec("ROLLBACK", on: conn)
      Error(MigrationFailed(filename: file, message: e.message))
    }
  }
}

fn parse_number(filename: String) -> Result(Int, MigrationError) {
  case string.split(filename, "_") {
    [num_str, ..] ->
      int.parse(num_str)
      |> result.replace_error(FilenameParseFailed(filename:))
    _ -> Error(FilenameParseFailed(filename:))
  }
}
