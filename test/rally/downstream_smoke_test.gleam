import gleam/option.{type Option, Some}
import gleam/string
import rally/internal/init
import simplifile

@external(erlang, "rally_cli_ffi", "find_executable")
fn find_executable(name: String) -> Option(String)

@external(erlang, "rally_cli_ffi", "run_in_dir")
fn run_in_dir(
  program: String,
  args: List(String),
  dir: String,
) -> #(Int, String)

fn rally_root() -> String {
  let assert Ok(cwd) = simplifile.current_directory()
  cwd
}

fn make_temp_dir() -> String {
  let path = "/tmp/rally_downstream_smoke"
  let _ = simplifile.delete(file_or_dir_at: path)
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn cleanup(path: String) -> Nil {
  let _ = simplifile.delete(file_or_dir_at: path)
  Nil
}

fn assert_no_warning(output: String, phase: String, dir: String) -> Nil {
  case string.contains(output, "warning:") {
    False -> Nil
    True -> {
      cleanup(dir)
      panic as { phase <> " emitted warnings: " <> output }
    }
  }
}

pub fn scaffold_builds_without_warnings_test() {
  let root = rally_root()
  let proute_root = root <> "/../proute"
  let dir = make_temp_dir()
  let assert Some(gleam) = find_executable("gleam")
  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  let patched =
    toml
    |> string.replace(
      "rally = \">= 1.0.0 and < 2.0.0\"",
      "rally = { path = \"" <> root <> "\" }",
    )
    |> string.replace(
      "proute = \">= 0.1.0 and < 1.0.0\"",
      "proute = { path = \"" <> proute_root <> "\" }",
    )
  let assert Ok(Nil) = simplifile.write(dir <> "/gleam.toml", patched)

  let #(migrate_exit, migrate_out) =
    run_in_dir(gleam, ["run", "-m", "rally", "migrate"], dir)
  case migrate_exit {
    0 ->
      case string.contains(migrate_out, "rally: marmot migrate") {
        True -> Nil
        False -> {
          cleanup(dir)
          panic as {
            "rally migrate did not delegate to Marmot: " <> migrate_out
          }
        }
      }
    _ -> {
      cleanup(dir)
      panic as { "rally migrate failed: " <> migrate_out }
    }
  }

  let #(reset_exit, reset_out) =
    run_in_dir(gleam, ["run", "-m", "rally", "reset"], dir)
  case reset_exit {
    0 ->
      case string.contains(reset_out, "rally: marmot reset") {
        True -> Nil
        False -> {
          cleanup(dir)
          panic as { "rally reset did not delegate to Marmot: " <> reset_out }
        }
      }
    _ -> {
      cleanup(dir)
      panic as { "rally reset failed: " <> reset_out }
    }
  }

  let assert Ok(Nil) =
    simplifile.create_directory_all(dir <> "/src/generated/stale")
  let assert Ok(Nil) =
    simplifile.write(dir <> "/src/generated/stale/old.txt", "stale")
  let #(regen_exit, regen_out) =
    run_in_dir(gleam, ["run", "-m", "rally", "regen"], dir)
  case regen_exit {
    0 ->
      case simplifile.read(dir <> "/src/generated/stale/old.txt") {
        Error(_) -> Nil
        Ok(_) -> {
          cleanup(dir)
          panic as { "rally regen left stale generated file: " <> regen_out }
        }
      }
    _ -> {
      cleanup(dir)
      panic as { "rally regen failed: " <> regen_out }
    }
  }

  let #(rally_build_exit, rally_build_out) =
    run_in_dir(gleam, ["run", "-m", "rally", "build"], dir)
  case rally_build_exit {
    0 -> Nil
    _ -> {
      cleanup(dir)
      panic as { "rally build failed: " <> rally_build_out }
    }
  }

  let #(build_exit, build_out) = run_in_dir(gleam, ["build"], dir)
  case build_exit {
    0 -> Nil
    _ -> {
      cleanup(dir)
      panic as { "build failed: " <> build_out }
    }
  }
  assert_no_warning(build_out, "build", dir)

  cleanup(dir)
}

pub fn scoreboard_example_build_test() {
  let dir = rally_root() <> "/../rally-scoreboard-example"
  let assert Some(gleam) = find_executable("gleam")
  let #(rally_build_exit, rally_build_out) =
    run_in_dir(gleam, ["run", "-m", "rally", "build"], dir)
  case rally_build_exit {
    0 -> Nil
    _ -> panic as { "Rally Scoreboard rally build failed: " <> rally_build_out }
  }
}
