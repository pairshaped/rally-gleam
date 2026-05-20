import gleam/dynamic/decode
import gleeunit/should
import rally/runtime/migrate
import simplifile
import sqlight

pub fn invalid_sql_migration_filename_returns_error_test() {
  let dir = fresh_dir("invalid_filename")
  let assert Ok(Nil) =
    simplifile.write(
      to: dir <> "/oops.sql",
      contents: "CREATE TABLE ignored (id INTEGER);",
    )
  let assert Ok(conn) = sqlight.open(":memory:")

  let assert Error(migrate.FilenameParseFailed(filename: "oops.sql")) =
    migrate.run(conn:, dir:)
}

pub fn corrupted_schema_migrations_table_returns_error_test() {
  let dir = fresh_dir("corrupted")
  let assert Ok(Nil) =
    simplifile.write(
      to: dir <> "/001_create_items.sql",
      contents: "CREATE TABLE items (id INTEGER PRIMARY KEY);",
    )
  let assert Ok(conn) = sqlight.open(":memory:")

  let assert Ok(_) =
    sqlight.exec(
      "CREATE TABLE schema_migrations (last_migration INTEGER NOT NULL);
       INSERT INTO schema_migrations (last_migration) VALUES (1);
       INSERT INTO schema_migrations (last_migration) VALUES (2);",
      on: conn,
    )

  let assert Error(migrate.SchemaTableCorrupted(row_count: 2)) =
    migrate.run(conn:, dir:)
}

pub fn failed_migration_rolls_back_and_keeps_version_test() {
  let dir = fresh_dir("rollback")
  let assert Ok(Nil) =
    simplifile.write(
      to: dir <> "/001_create_items.sql",
      contents: "CREATE TABLE items (id INTEGER PRIMARY KEY);",
    )
  let assert Ok(Nil) =
    simplifile.write(
      to: dir <> "/002_bad_insert.sql",
      contents: "INSERT INTO missing_table (id) VALUES (1);",
    )
  let assert Ok(conn) = sqlight.open(":memory:")

  let assert Error(migrate.MigrationFailed(filename: "002_bad_insert.sql", ..)) =
    migrate.run(conn:, dir:)

  migration_version(conn) |> should.equal(1)
}

fn fresh_dir(name: String) -> String {
  let path = "/tmp/rally_migrate_test_" <> name
  let _ = simplifile.delete(file_or_dir_at: path)
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn migration_version(conn: sqlight.Connection) -> Int {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT last_migration FROM schema_migrations",
      on: conn,
      with: [],
      expecting: {
        use version <- decode.field(0, decode.int)
        decode.success(version)
      },
    )
  let assert [version] = rows
  version
}
