//// CLI entry point for Rally. The default build path follows the Rally
//// Scoreboard Example pipeline: Marmot, Proute, Rally load/save
//// generation, and Erlang/JavaScript builds.

import argv
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import libero
import libero/gen_error
import rally/internal/format
import rally/internal/generator/load_rpc
import rally/internal/init as rally_init
import rally/runtime/env
import simplifile
import tom

pub type RallyError {
  RallyError(message: String)
}

pub fn main() -> Nil {
  let args = argv.load().arguments
  case run(args) {
    Ok(msg) -> io.println("rally: " <> msg)
    Error(RallyError(msg)) -> {
      io.println_error("rally error: " <> msg)
      halt(1)
    }
  }
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

fn read_project_toml() -> Result(dict.Dict(String, tom.Toml), RallyError) {
  use toml_str <- result.try(
    simplifile.read("gleam.toml")
    |> result.map_error(fn(e) {
      RallyError("Cannot read gleam.toml: " <> simplifile.describe_error(e))
    }),
  )
  use toml_map <- result.try(
    tom.parse(toml_str)
    |> result.map_error(fn(e) {
      RallyError("Invalid gleam.toml: " <> tom_error_to_string(e))
    }),
  )
  Ok(toml_map)
}

fn run(args: List(String)) -> Result(String, RallyError) {
  case args {
    ["init"] -> {
      use Nil <- result.try(
        rally_init.init_project(".")
        |> result.map_error(fn(msg) { RallyError("init error: " <> msg) }),
      )
      Ok("initialized project")
    }
    ["migrate"] -> run_migrate()
    ["regen"] -> run_regen()
    ["reset"] -> run_reset()
    ["server"] | ["server", "restart"] -> run_server()
    ["build"] -> run_rally_build()
    [] | ["gen"] -> run_rally_codegen()
    _ ->
      Error(RallyError(
        "Unknown command. Usage: rally init | rally migrate | rally reset | rally regen | rally server | rally build | rally gen",
      ))
  }
}

fn run_rally_source_codegen_with_toml(
  toml_map: dict.Dict(String, tom.Toml),
) -> Result(String, RallyError) {
  use Nil <- result.try(ensure_dependency(
    toml_map,
    package: "libero",
    reason: "Rally codegen uses Libero to generate wire codecs.",
  ))
  use push_contract <- result.try(rally_push_contract_from_toml(toml_map))
  use load_context <- result.try(rally_load_context_from_toml(toml_map))
  use loads <- result.try(
    load_rpc.discover("src")
    |> result.map_error(fn(msg) {
      RallyError("Rally source discovery error: " <> msg)
    }),
  )
  use libero_files <- result.try(generate_rally_libero_files(
    loads:,
    push_contract:,
    package: package_name_from_toml(toml_map),
    dependency_packages: dependency_names_from_toml(toml_map),
  ))
  let files =
    list.append(
      load_rpc.generate(loads:, push_contract:, load_context:),
      libero_files,
    )
  use Nil <- result.try(
    write_rally_generated_files(files)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  Ok(
    "generated "
    <> int.to_string(list.length(loads))
    <> " page load/save contract(s)",
  )
}

fn generate_rally_libero_files(
  loads loads: List(load_rpc.LoadRpc),
  push_contract push_contract: option.Option(load_rpc.PushContract),
  package package: String,
  dependency_packages dependency_packages: List(String),
) -> Result(List(load_rpc.GeneratedFile), RallyError) {
  let seeds = load_rpc.libero_type_seeds(loads:, push_contract:)
  use discovered <- result.try(
    libero.walk(seeds)
    |> result.map_error(fn(errors) {
      list.each(errors, gen_error.print_error)
      RallyError("Libero type discovery failed for Rally wire types")
    }),
  )
  let atoms_module = "generated@libero_atoms"
  let wire_module = "generated@libero_wire"
  let decoders_module = "generated/libero/decoders"
  let atoms_erl =
    libero.generate_atoms(
      discovered:,
      atoms_module:,
      wire_module: option.Some(wire_module),
    )
  use wire_erl <- result.try(
    case libero.generate_wire_erl(discovered:, wire_module:) {
      Ok(source) -> Ok(source)
      Error(err) -> {
        gen_error.print_error(err)
        Error(RallyError("Libero wire generation failed for Rally wire types"))
      }
    },
  )
  let decoders_js =
    libero.generate_decoders_ffi(discovered:, package:, dependency_packages:)
  let decoders_gleam = libero.generate_decoders_gleam()
  let etf_gleam =
    libero.generate_etf_codec_module(atoms_module:, decoders_module:)
  let contract =
    libero.generate_json_contract(discovered:, push_types: [], ssr_models: [])

  Ok([
    load_rpc.GeneratedFile("src/generated/libero/decoders_ffi.mjs", decoders_js),
    load_rpc.GeneratedFile(
      "src/generated/libero/decoders.gleam",
      decoders_gleam,
    ),
    load_rpc.GeneratedFile("src/generated/libero/etf.gleam", etf_gleam),
    load_rpc.GeneratedFile(
      "src/generated/libero/" <> atoms_module <> ".erl",
      atoms_erl,
    ),
    load_rpc.GeneratedFile(
      "src/generated/libero/" <> wire_module <> ".erl",
      wire_erl,
    ),
    load_rpc.GeneratedFile("src/generated/libero/contract.json", contract),
  ])
}

fn rally_push_contract_from_toml(
  toml_map: dict.Dict(String, tom.Toml),
) -> Result(option.Option(load_rpc.PushContract), RallyError) {
  case tom.get_table(toml_map, ["tools", "rally", "push"]) {
    Ok(push_config) -> parse_push_contract(push_config, "[tools.rally.push]")
    Error(tom.NotFound(_)) -> Ok(option.None)
    Error(err) ->
      Error(RallyError(
        "Invalid [tools.rally.push]: " <> tom_get_error_to_string(err),
      ))
  }
}

fn parse_push_contract(
  push_config: dict.Dict(String, tom.Toml),
  table_name: String,
) -> Result(option.Option(load_rpc.PushContract), RallyError) {
  use module_path <- result.try(
    tom.get_string(push_config, ["module"])
    |> result.map_error(fn(err) {
      RallyError(
        "Invalid " <> table_name <> " module: " <> tom_get_error_to_string(err),
      )
    }),
  )
  use type_name <- result.try(
    tom.get_string(push_config, ["type"])
    |> result.map_error(fn(err) {
      RallyError(
        "Invalid " <> table_name <> " type: " <> tom_get_error_to_string(err),
      )
    }),
  )
  Ok(
    option.Some(load_rpc.PushContract(
      module_path: module_path,
      type_name: type_name,
    )),
  )
}

fn rally_load_context_from_toml(
  toml_map: dict.Dict(String, tom.Toml),
) -> Result(option.Option(load_rpc.LoadContext), RallyError) {
  case tom.get_table(toml_map, ["tools", "rally", "context"]) {
    Ok(context_config) ->
      parse_load_context(context_config, "[tools.rally.context]")
    Error(tom.NotFound(_)) -> Ok(option.None)
    Error(err) ->
      Error(RallyError(
        "Invalid [tools.rally.context]: " <> tom_get_error_to_string(err),
      ))
  }
}

fn parse_load_context(
  context_config: dict.Dict(String, tom.Toml),
  table_name: String,
) -> Result(option.Option(load_rpc.LoadContext), RallyError) {
  use module_path <- result.try(
    tom.get_string(context_config, ["module"])
    |> result.map_error(fn(err) {
      RallyError(
        "Invalid " <> table_name <> " module: " <> tom_get_error_to_string(err),
      )
    }),
  )
  use type_name <- result.try(
    tom.get_string(context_config, ["type"])
    |> result.map_error(fn(err) {
      RallyError(
        "Invalid " <> table_name <> " type: " <> tom_get_error_to_string(err),
      )
    }),
  )
  Ok(
    option.Some(load_rpc.LoadContext(
      module_path: module_path,
      type_name: type_name,
    )),
  )
}

fn package_name_from_toml(toml_map: dict.Dict(String, tom.Toml)) -> String {
  tom.get_string(toml_map, ["name"])
  |> result.unwrap("app")
}

fn dependency_names_from_toml(
  toml_map: dict.Dict(String, tom.Toml),
) -> List(String) {
  tom.get_table(toml_map, ["dependencies"])
  |> result.map(dict.keys)
  |> result.unwrap([])
}

fn write_rally_generated_files(
  files: List(load_rpc.GeneratedFile),
) -> Result(Nil, String) {
  list.try_fold(files, Nil, fn(_, file) {
    let load_rpc.GeneratedFile(path:, content:) = file
    write_file(path, content)
  })
}

fn run_rally_codegen() -> Result(String, RallyError) {
  use toml_map <- result.try(read_project_toml())
  use Nil <- result.try(run_marmot_if_configured(toml_map))
  use Nil <- result.try(run_proute_if_configured(toml_map))
  run_rally_source_codegen_with_toml(toml_map)
}

fn run_rally_build() -> Result(String, RallyError) {
  use _ <- result.try(run_rally_codegen())
  use gleam <- result.try(find_gleam())
  use Nil <- result.try(run_command(
    program: gleam,
    args: ["build", "--target", "erlang"],
    dir: ".",
    label: "erlang build",
  ))
  use Nil <- result.try(run_command(
    program: gleam,
    args: ["build", "--target", "javascript"],
    dir: ".",
    label: "javascript build",
  ))
  Ok("built Rally app")
}

fn run_migrate() -> Result(String, RallyError) {
  use toml_map <- result.try(read_project_toml())
  use Nil <- result.try(run_marmot_command_if_configured(
    toml_map,
    args: ["run", "-m", "marmot", "migrate"],
    label: "marmot migrate",
  ))
  Ok("migrate complete")
}

fn run_reset() -> Result(String, RallyError) {
  use toml_map <- result.try(read_project_toml())
  use Nil <- result.try(run_marmot_command_if_configured(
    toml_map,
    args: ["run", "-m", "marmot", "reset"],
    label: "marmot reset",
  ))
  Ok("reset complete")
}

fn run_regen() -> Result(String, RallyError) {
  use Nil <- result.try(
    simplifile.delete_all(paths: ["src/generated"])
    |> result.map_error(fn(e) {
      RallyError(
        "Cannot delete src/generated: " <> simplifile.describe_error(e),
      )
    }),
  )
  run_rally_codegen()
}

fn run_server() -> Result(String, RallyError) {
  use port <- result.try(server_port())
  let stopped = stop_port_listener(port)
  case stopped > 0 {
    True ->
      io.println(
        "rally: stopped "
        <> int.to_string(stopped)
        <> " process(es) on port "
        <> int.to_string(port),
      )
    False -> Nil
  }
  use gleam <- result.try(find_gleam())
  io.println("rally: server foreground on port " <> int.to_string(port))
  case run_interactive_in_dir(gleam, ["run"], ".") {
    0 -> Ok("server stopped")
    status ->
      Error(RallyError("server failed with exit code " <> int.to_string(status)))
  }
}

fn server_port() -> Result(Int, RallyError) {
  case env.get("PORT") {
    Ok(raw) ->
      case int.parse(raw) {
        Ok(port) -> Ok(port)
        Error(Nil) ->
          Error(RallyError(
            "Invalid PORT value: "
            <> raw
            <> ". Set PORT to an integer, for example PORT=8080.",
          ))
      }
    Error(Nil) -> Ok(8080)
  }
}

fn run_marmot_if_configured(
  toml_map: dict.Dict(String, tom.Toml),
) -> Result(Nil, RallyError) {
  run_marmot_command_if_configured(
    toml_map,
    args: ["run", "-m", "marmot"],
    label: "marmot codegen",
  )
}

fn run_marmot_command_if_configured(
  toml_map: dict.Dict(String, tom.Toml),
  args args: List(String),
  label label: String,
) -> Result(Nil, RallyError) {
  case should_run_marmot(toml_map) {
    True -> {
      use Nil <- result.try(ensure_dependency(
        toml_map,
        package: "marmot",
        reason: "Rally delegates this command to Marmot.",
      ))
      use gleam <- result.try(find_gleam())
      run_command(program: gleam, args:, dir: ".", label:)
    }
    False -> Ok(Nil)
  }
}

fn run_proute_if_configured(
  toml_map: dict.Dict(String, tom.Toml),
) -> Result(Nil, RallyError) {
  case simplifile.is_file("proute.toml") {
    Ok(True) -> {
      use Nil <- result.try(ensure_dependency(
        toml_map,
        package: "proute",
        reason: "Rally delegates route generation to Proute when proute.toml exists.",
      ))
      use gleam <- result.try(find_gleam())
      run_command(
        program: gleam,
        args: ["run", "-m", "proute"],
        dir: ".",
        label: "proute codegen",
      )
    }
    _ -> Ok(Nil)
  }
}

@internal
pub fn ensure_dependency(
  toml_map: dict.Dict(String, tom.Toml),
  package package: String,
  reason reason: String,
) -> Result(Nil, RallyError) {
  case dependency_present(toml_map, package) {
    True -> Ok(Nil)
    False ->
      Error(RallyError(
        "Missing dependency `"
        <> package
        <> "` in gleam.toml. "
        <> reason
        <> " Add it with `gleam add "
        <> package
        <> "`.",
      ))
  }
}

fn dependency_present(
  toml_map: dict.Dict(String, tom.Toml),
  package: String,
) -> Bool {
  has_dependency_in_section(toml_map, ["dependencies"], package)
  || has_dependency_in_section(toml_map, ["dev-dependencies"], package)
  || has_dependency_in_section(toml_map, ["dev_dependencies"], package)
}

fn has_dependency_in_section(
  toml_map: dict.Dict(String, tom.Toml),
  section: List(String),
  package: String,
) -> Bool {
  case tom.get(toml_map, list.append(section, [package])) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn should_run_marmot(toml_map: dict.Dict(String, tom.Toml)) -> Bool {
  case tom.get_table(toml_map, ["tools", "marmot"]) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn find_gleam() -> Result(String, RallyError) {
  case find_executable("gleam") {
    option.Some(path) -> Ok(path)
    option.None -> Error(RallyError("Could not find `gleam` on PATH"))
  }
}

fn run_command(
  program program: String,
  args args: List(String),
  dir dir: String,
  label label: String,
) -> Result(Nil, RallyError) {
  io.println("rally: " <> label)
  let #(status, output) = run_in_dir(program, args, dir)
  case output == "" {
    True -> Nil
    False -> io.println(output)
  }
  case status {
    0 -> Ok(Nil)
    _ ->
      Error(RallyError(
        label <> " failed with exit code " <> int.to_string(status),
      ))
  }
}

fn write_file(path: String, content: String) -> Result(Nil, String) {
  let formatted = case string.ends_with(path, ".gleam") {
    True -> format.format_gleam(content)
    False -> content
  }
  write_if_changed(path, formatted)
}

fn write_if_changed(path: String, content: String) -> Result(Nil, String) {
  case simplifile.read(path) {
    Ok(existing) if existing == content -> Ok(Nil)
    _ -> {
      use _ <- result.try(
        simplifile.create_directory_all(dirname(path))
        |> result.map_error(fn(e) {
          "Failed to create directory for "
          <> path
          <> ": "
          <> simplifile.describe_error(e)
        }),
      )
      simplifile.write(path, content)
      |> result.map_error(fn(e) {
        "Failed to write " <> path <> ": " <> simplifile.describe_error(e)
      })
    }
  }
}

fn dirname(path: String) -> String {
  case string.split(path, "/") |> list.reverse {
    [_last, ..rest] -> string.join(list.reverse(rest), "/")
    [] -> "."
  }
}

fn tom_error_to_string(e: tom.ParseError) -> String {
  case e {
    tom.Unexpected(got:, expected:) ->
      "unexpected character '" <> got <> "', expected " <> expected
    tom.KeyAlreadyInUse(key:) -> "duplicate key: " <> string.join(key, ".")
  }
}

fn tom_get_error_to_string(e: tom.GetError) -> String {
  case e {
    tom.NotFound(key:) -> "key not found: " <> string.join(key, ".")
    tom.WrongType(key:, expected:, got:) ->
      "expected "
      <> expected
      <> ", got "
      <> got
      <> " at "
      <> string.join(key, ".")
  }
}

@external(erlang, "rally_cli_ffi", "find_executable")
fn find_executable(name: String) -> option.Option(String)

@external(erlang, "rally_cli_ffi", "run_in_dir")
fn run_in_dir(
  program: String,
  args: List(String),
  dir: String,
) -> #(Int, String)

@external(erlang, "rally_cli_ffi", "run_interactive_in_dir")
fn run_interactive_in_dir(
  program: String,
  args: List(String),
  dir: String,
) -> Int

@external(erlang, "rally_cli_ffi", "stop_port_listener")
fn stop_port_listener(port: Int) -> Int
