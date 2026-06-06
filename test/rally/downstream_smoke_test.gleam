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

@external(erlang, "timer", "sleep")
fn sleep(ms: Int) -> Nil

const cli_build_cache = "build/downstream_smoke_shared"

const cli_build_cache_lock = "build/downstream_smoke_shared.lock"

const cli_build_cache_ready = "build/downstream_smoke_shared/.ready"

fn rally_root() -> String {
  let assert Ok(cwd) = simplifile.current_directory()
  cwd
}

fn make_temp_dir() -> String {
  let path = rally_root() <> "/tmp/rally_downstream_smoke"
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
  let dir = make_temp_dir()
  let assert Some(gleam) = find_executable("gleam")
  let assert Ok(Nil) = init.init_project(dir)
  link_cli_project_build(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  let patched =
    toml
    |> string.replace(
      "rally = \">= 1.0.0 and < 2.0.0\"",
      "rally = { path = \"" <> root <> "\" }",
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

fn link_cli_project_build(base: String) -> Nil {
  // Reuse Rally's compiled dependency cache so the scaffold smoke test does not
  // rebuild esqlite's native NIF for every fresh temp project.
  ensure_cli_build_cache()
  let assert Ok(_) =
    simplifile.create_symlink(
      rally_root() <> "/" <> cli_build_cache,
      base <> "/build",
    )
  Nil
}

fn ensure_cli_build_cache() -> Nil {
  case simplifile.is_file(cli_build_cache_ready) {
    Ok(True) -> Nil
    _ -> prepare_cli_build_cache()
  }
}

fn prepare_cli_build_cache() -> Nil {
  case simplifile.create_directory(cli_build_cache_lock) {
    Ok(_) -> {
      let _ = simplifile.delete(cli_build_cache)
      let assert Ok(_) = simplifile.create_directory_all(cli_build_cache)
      let assert Ok(_) =
        simplifile.copy_directory(
          at: "build/packages",
          to: cli_build_cache <> "/packages",
        )
      let assert Ok(_) =
        simplifile.copy_directory(
          at: "build/dev",
          to: cli_build_cache <> "/dev",
        )
      let assert Ok(_) = simplifile.write(cli_build_cache_ready, "ready")
      let _ = simplifile.delete(cli_build_cache_lock)
      Nil
    }
    Error(_) -> wait_for_cli_build_cache(100)
  }
}

fn wait_for_cli_build_cache(attempts: Int) -> Nil {
  case simplifile.is_file(cli_build_cache_ready) {
    Ok(True) -> Nil
    _ if attempts > 0 -> {
      sleep(100)
      wait_for_cli_build_cache(attempts - 1)
    }
    _ -> panic as "Timed out waiting for shared CLI build cache"
  }
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
