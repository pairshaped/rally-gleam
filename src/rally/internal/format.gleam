//// Run `gleam format` on generated Gleam code.
//// Writes code to a temp file, runs the formatter, reads back the result.
//// Falls back to the original string if formatting fails.

import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile

type WarningMode {
  Warn
  Quiet
}

pub fn format_gleam(code: String) -> String {
  format_gleam_with_warnings(code, Warn)
}

pub fn format_gleam_quiet(code: String) -> String {
  format_gleam_with_warnings(code, Quiet)
}

fn format_gleam_with_warnings(code: String, warnings: WarningMode) -> String {
  let suffix = format_unique_id()
  let tmp_dir = get_tmp_dir()
  let tmp = tmp_dir <> "/rally_fmt_" <> suffix <> ".gleam"
  case simplifile.write(tmp, code) {
    Ok(_) -> {
      let formatted = run_format(tmp, code, warnings)
      let _delete_result = simplifile.delete(tmp)
      formatted
    }
    _ -> {
      warn(
        warnings,
        "warning: could not write temp file for formatting, skipping gleam format",
      )
      code
    }
  }
}

fn run_format(tmp: String, fallback: String, warnings: WarningMode) -> String {
  case find_executable("gleam") {
    None -> {
      warn(warnings, "warning: gleam not found on PATH, skipping format")
      fallback
    }
    Some(path) -> {
      let exit_code = run_executable(path, ["format", tmp])
      case exit_code {
        0 ->
          simplifile.read(tmp)
          |> result.unwrap(fallback)
        _ -> {
          // Expected during tests: generated code imports target-project
          // modules (e.g. generated/admin/rpc_dispatch) that don't exist in
          // Rally's own dependency tree. Formatter exits non-zero but the
          // fallback (unformatted original) is correct.
          warn(
            warnings,
            "warning: gleam format failed (exit code "
              <> int.to_string(exit_code)
              <> "), using unformatted output",
          )
          fallback
        }
      }
    }
  }
}

fn warn(warnings: WarningMode, message: String) -> Nil {
  case warnings {
    Warn -> io.println_error(message)
    Quiet -> Nil
  }
}

@external(erlang, "rally_cli_ffi", "find_executable")
fn find_executable(name: String) -> Option(String)

@external(erlang, "rally_cli_ffi", "run_executable")
fn run_executable(program: String, args: List(String)) -> Int

fn get_tmp_dir() -> String {
  let dir = "./tmp/rally_format"
  let _dir_result = simplifile.create_directory_all(dir)
  dir
}

@external(erlang, "rally_cli_ffi", "unique_id")
fn format_unique_id() -> String
