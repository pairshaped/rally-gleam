import gleam/string
import gleeunit/should
import rally/internal/format

pub fn format_gleam_keeps_valid_syntax_test() {
  let source = "pub fn add(x: Int, y: Int) -> Int {\n  x + y\n}\n"
  let formatted = format.format_gleam(source)
  // gleam format should be on PATH in dev/test environments
  formatted |> string.contains("pub fn add") |> should.be_true()
}

pub fn format_gleam_idempotent_test() {
  let source = "pub fn identity(x) { x }\n"
  let once = format.format_gleam(source)
  let twice = format.format_gleam(once)
  twice |> should.equal(once)
}

pub fn format_fallback_on_invalid_gleam_syntax_test() {
  // If gleam format exits non-zero (bad syntax), the original is returned unchanged.
  let source = "this is not valid gleam"
  let formatted = format.format_gleam_quiet(source)
  formatted |> should.equal(source)
}
