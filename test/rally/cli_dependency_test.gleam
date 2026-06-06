import gleam/string
import gleeunit/should
import rally
import tom

pub fn dependency_check_accepts_runtime_dependency_test() {
  let assert Ok(toml) =
    tom.parse("[dependencies]\nlibero = \">= 7.0.0 and < 8.0.0\"\n")

  rally.ensure_dependency(toml, package: "libero", reason: "needed")
  |> should.be_ok()
}

pub fn dependency_check_accepts_dev_dependency_test() {
  let assert Ok(toml) =
    tom.parse("[dev-dependencies]\nmarmot = \">= 1.7.2 and < 2.0.0\"\n")

  rally.ensure_dependency(toml, package: "marmot", reason: "needed")
  |> should.be_ok()
}

pub fn dependency_check_accepts_underscore_dev_dependency_test() {
  let assert Ok(toml) =
    tom.parse("[dev_dependencies]\nglinter = \">= 2.19.0 and < 3.0.0\"\n")

  rally.ensure_dependency(toml, package: "glinter", reason: "needed")
  |> should.be_ok()
}

pub fn dependency_check_returns_clear_error_test() {
  let assert Ok(toml) = tom.parse("[dependencies]\nrally = \"1.0.0\"\n")

  let assert Error(rally.RallyError(message)) =
    rally.ensure_dependency(
      toml,
      package: "marmot",
      reason: "Rally delegates this command to Marmot.",
    )

  message |> string_contains("Missing dependency `marmot`") |> should.be_true()
  message |> string_contains("gleam add marmot") |> should.be_true()
}

fn string_contains(haystack: String, needle: String) -> Bool {
  haystack
  |> string.contains(needle)
}
