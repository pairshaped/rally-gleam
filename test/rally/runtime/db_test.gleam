import gleam/dynamic/decode
import gleeunit/should
import rally/runtime/db
import sqlight

pub fn transaction_rolls_back_failed_body_test() {
  let assert Ok(conn) = sqlight.open(":memory:")
  let assert Ok(_) =
    sqlight.exec("CREATE TABLE items (id INTEGER PRIMARY KEY);", on: conn)

  let result =
    db.transaction(conn, fn() {
      let assert Ok(_) =
        sqlight.exec("INSERT INTO items (id) VALUES (1);", on: conn)
      sqlight.exec("INSERT INTO missing_table (id) VALUES (1);", on: conn)
    })

  let assert Error(_) = result
  count_items(conn) |> should.equal(0)
}

pub fn nested_transaction_rolls_back_inner_and_commits_outer_test() {
  let assert Ok(conn) = sqlight.open(":memory:")
  let assert Ok(_) =
    sqlight.exec("CREATE TABLE items (id INTEGER PRIMARY KEY);", on: conn)

  let result =
    db.transaction(conn, fn() {
      let assert Ok(_) =
        sqlight.exec("INSERT INTO items (id) VALUES (1);", on: conn)
      let assert Error(_) =
        db.transaction(conn, fn() {
          let assert Ok(_) =
            sqlight.exec("INSERT INTO items (id) VALUES (2);", on: conn)
          sqlight.exec("INSERT INTO missing_table (id) VALUES (1);", on: conn)
        })
      Ok(Nil)
    })

  result |> should.equal(Ok(Nil))
  count_items(conn) |> should.equal(1)
}

fn count_items(conn: sqlight.Connection) -> Int {
  let assert Ok(rows) =
    sqlight.query("SELECT COUNT(*) FROM items", on: conn, with: [], expecting: {
      use count <- decode.field(0, decode.int)
      decode.success(count)
    })
  let assert [count] = rows
  count
}
