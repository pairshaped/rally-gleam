import gleeunit/should
import helpers/datetime

pub fn now_unix_returns_plausible_timestamp_test() {
  let ts = datetime.now_unix()

  // Should be a positive integer
  { ts > 0 }
  |> should.be_true

  // Should be after 2020-01-01 (1577836800) and before 2100-01-01 (4102444800)
  { ts > 1_577_836_800 }
  |> should.be_true

  { ts < 4_102_444_800 }
  |> should.be_true
}
