//// CLI entry point for Rally codegen. Reads [[tools.rally.clients]]
//// from gleam.toml and runs one codegen pipeline per client namespace:
//// scan routes, parse pages, discover handlers via libero, generate
//// server and client code, tree-shake, resolve dependencies, write output.

import argv
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import libero
import libero/codegen_dispatch.{ExtraParam}
import libero/etf/codegen_erl
import libero/field_type
import libero/gen_error
import libero/json/contract as json_contract
import libero/scanner as libero_scanner
import libero/walker.{type DiscoveredType}
import rally/internal/dependency_resolver
import rally/internal/format
import rally/internal/generator
import rally/internal/generator/client
import rally/internal/generator/codec
import rally/internal/generator/http_handler
import rally/internal/generator/ssr_handler
import rally/internal/generator/ws_handler
import rally/internal/init as rally_init
import rally/internal/parser
import rally/internal/scanner
import rally/internal/tree_shaker
import rally/internal/types.{type ScanConfig, ScanConfig}
import rally_runtime/db
import rally_runtime/migrate
import simplifile
import tom

type RallyError {
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

fn read_configs() -> Result(List(ScanConfig), RallyError) {
  use toml_map <- result.try(read_project_toml())

  let rally_config =
    tom.get_table(toml_map, ["tools", "rally"])
    |> result.unwrap(dict.new())

  let server_deps =
    tom.get_table(toml_map, ["dependencies"])
    |> result.unwrap(dict.new())

  let rally_package_path = resolve_rally_package_path(server_deps)

  case tom.get_array(rally_config, ["clients"]) {
    Ok(clients) -> {
      use configs <- result.try(
        list.try_map(clients, fn(client) {
          case client {
            tom.Table(cfg) | tom.InlineTable(cfg) ->
              read_client_config(
                client_config: cfg,
                server_deps:,
                rally_package_path:,
              )
            _ ->
              Error(RallyError(
                "Each [[tools.rally.clients]] entry must be a table",
              ))
          }
        }),
      )
      case configs {
        [] ->
          Ok([
            read_legacy_config(rally_config:, server_deps:, rally_package_path:),
          ])
        _ -> Ok(configs)
      }
    }
    _ ->
      Ok([read_legacy_config(rally_config:, server_deps:, rally_package_path:)])
  }
}

pub fn resolve_rally_package_path(
  server_deps: dict.Dict(String, tom.Toml),
) -> String {
  case dict.get(server_deps, "rally") {
    Ok(tom.InlineTable(rally_dep)) | Ok(tom.Table(rally_dep)) ->
      case dict.get(rally_dep, "path") {
        Ok(tom.String(path)) -> path
        _ -> "build/packages/rally"
      }
    Ok(_) -> "build/packages/rally"
    Error(Nil) -> "."
  }
}

fn read_client_config(
  client_config client_config: dict.Dict(String, tom.Toml),
  server_deps server_deps: dict.Dict(String, tom.Toml),
  rally_package_path rally_package_path: String,
) -> Result(ScanConfig, RallyError) {
  use namespace <- result.try(
    tom.get_string(client_config, ["namespace"])
    |> result.map_error(fn(e) {
      RallyError(
        "Each [[tools.rally.clients]] entry needs namespace = \"...\": "
        <> tom_get_error_to_string(e),
      )
    }),
  )
  let route_root =
    tom.get_string(client_config, ["route_root"])
    |> result.unwrap("/" <> namespace)
  let protocol =
    tom.get_string(client_config, ["protocol"])
    |> result.unwrap("etf")
  let protocol = case protocol {
    "etf" -> protocol
    "json" -> protocol
    other -> {
      io.println_error(
        "warning: unknown protocol \""
        <> other
        <> "\" in [[tools.rally.clients]], defaulting to \"etf\"",
      )
      "etf"
    }
  }
  Ok(ScanConfig(
    pages_root: "src/" <> namespace <> "/pages",
    output_route: "src/generated/" <> namespace <> "/router.gleam",
    output_dispatch: "src/generated/" <> namespace <> "/page_dispatch.gleam",
    output_server_dispatch: "src/generated/"
      <> namespace
      <> "/rpc_dispatch.gleam",
    output_server_atoms: "src/generated@" <> namespace <> "@rpc_atoms.erl",
    atoms_module: "generated@" <> namespace <> "@rpc_atoms",
    output_server_wire: "src/generated@" <> namespace <> "@rpc_wire.erl",
    wire_module: "generated@" <> namespace <> "@rpc_wire",
    output_ssr: "src/generated/" <> namespace <> "/ssr_handler.gleam",
    output_ws: "src/generated/" <> namespace <> "/ws_handler.gleam",
    output_http: "src/generated/" <> namespace <> "/http_handler.gleam",
    client_root: ".generated_clients/" <> namespace,
    route_root:,
    rally_package_path:,
    shell_file: "src/" <> namespace <> "/shell.html",
    server_deps:,
    protocol:,
  ))
}

fn read_legacy_config(
  rally_config rally_config: dict.Dict(String, tom.Toml),
  server_deps server_deps: dict.Dict(String, tom.Toml),
  rally_package_path rally_package_path: String,
) -> ScanConfig {
  let pages_root =
    tom.get_string(rally_config, ["pages_root"])
    |> result.unwrap("src/pages")
  let output_route =
    tom.get_string(rally_config, ["output_route"])
    |> result.unwrap("src/generated/router.gleam")
  let output_dispatch =
    tom.get_string(rally_config, ["output_dispatch"])
    |> result.unwrap("src/generated/page_dispatch.gleam")
  let output_server_dispatch =
    tom.get_string(rally_config, ["output_server_dispatch"])
    |> result.unwrap("src/generated/rpc_dispatch.gleam")
  let output_server_atoms =
    tom.get_string(rally_config, ["output_server_atoms"])
    |> result.unwrap("src/generated@rpc_atoms.erl")
  let atoms_module = "generated@rpc_atoms"
  let wire_module = "generated@rpc_wire"
  let output_ssr =
    tom.get_string(rally_config, ["output_ssr"])
    |> result.unwrap("src/generated/ssr_handler.gleam")
  let output_ws =
    tom.get_string(rally_config, ["output_ws"])
    |> result.unwrap("src/generated/ws_handler.gleam")
  let output_http =
    tom.get_string(rally_config, ["output_http"])
    |> result.unwrap("src/generated/http_handler.gleam")
  let client_root =
    tom.get_string(rally_config, ["client_root"])
    |> result.unwrap(".generated_clients")
  let route_root =
    tom.get_string(rally_config, ["route_root"])
    |> result.unwrap("/")
  let shell_file =
    tom.get_string(rally_config, ["shell_file"])
    |> result.unwrap("src/shell.html")
  let protocol = "etf"

  ScanConfig(
    pages_root:,
    output_route:,
    output_dispatch:,
    output_server_dispatch:,
    output_server_atoms:,
    atoms_module:,
    output_server_wire: "src/generated@rpc_wire.erl",
    wire_module:,
    output_ssr:,
    output_ws:,
    output_http:,
    client_root:,
    route_root:,
    rally_package_path:,
    shell_file:,
    server_deps:,
    protocol:,
  )
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
    ["build"] -> {
      use configs <- result.try(read_configs())
      use Nil <- result.try(build_project(configs))
      Ok("built " <> int.to_string(list.length(configs)) <> " client(s)")
    }
    [] | ["gen"] -> {
      use configs <- result.try(read_configs())
      use Nil <- result.try(list.try_each(configs, generate_for_config))
      Ok(int.to_string(list.length(configs)) <> " client(s)")
    }
    _ ->
      Error(RallyError(
        "Unknown command. Usage: rally init | rally migrate | rally build | rally gen",
      ))
  }
}

fn build_project(configs: List(ScanConfig)) -> Result(Nil, RallyError) {
  use gleam <- result.try(find_gleam())
  use Nil <- result.try(list.try_each(configs, generate_for_config))
  list.try_each(configs, fn(config) {
    run_command(
      program: gleam,
      args: ["build", "--target", "javascript"],
      dir: config.client_root,
      label: "client build for " <> config.client_root,
    )
  })
}

fn run_migrate() -> Result(String, RallyError) {
  use toml_map <- result.try(read_project_toml())
  let db_path =
    tom.get_string(toml_map, ["tools", "marmot", "database"])
    |> result.unwrap("app.db")

  use Nil <- result.try(ensure_db_parent_dir(db_path))
  use Nil <- result.try(run_migrations(db_path))
  use Nil <- result.try(run_marmot_if_configured(toml_map))
  Ok("migrate complete")
}

fn ensure_db_parent_dir(db_path: String) -> Result(Nil, RallyError) {
  let dir = dirname(db_path)
  case dir == "" || dir == "." {
    True -> Ok(Nil)
    False ->
      simplifile.create_directory_all(dir)
      |> result.map_error(fn(e) {
        RallyError(
          "Cannot create database directory "
          <> dir
          <> ": "
          <> simplifile.describe_error(e),
        )
      })
  }
}

fn run_migrations(db_path: String) -> Result(Nil, RallyError) {
  case simplifile.is_directory("migrations") {
    Ok(True) -> {
      io.println("rally: migrations (" <> db_path <> ")")
      use conn <- result.try(
        db.open(db_path)
        |> result.map_error(fn(e) {
          RallyError("Cannot open " <> db_path <> ": " <> e.message)
        }),
      )
      migrate.run(conn:, dir: "migrations")
      |> result.map_error(fn(e) { RallyError(migrate.error_to_string(e)) })
    }
    _ -> Ok(Nil)
  }
}

fn run_marmot_if_configured(
  toml_map: dict.Dict(String, tom.Toml),
) -> Result(Nil, RallyError) {
  case should_run_marmot(toml_map) {
    True -> {
      use gleam <- result.try(find_gleam())
      run_command(
        program: gleam,
        args: ["run", "-m", "marmot"],
        dir: ".",
        label: "marmot codegen",
      )
    }
    False -> Ok(Nil)
  }
}

fn should_run_marmot(toml_map: dict.Dict(String, tom.Toml)) -> Bool {
  case tom.get_table(toml_map, ["tools", "marmot"]) {
    Ok(_) -> {
      let sql_dir =
        tom.get_string(toml_map, ["tools", "marmot", "sql_dir"])
        |> result.unwrap("src/sql")
      case simplifile.get_files(sql_dir) {
        Ok(files) ->
          list.any(files, fn(file) { string.ends_with(file, ".sql") })
        Error(_) -> False
      }
    }
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

fn generate_for_config(config: ScanConfig) -> Result(Nil, RallyError) {
  use routes <- result.try(
    scanner.scan(config)
    |> result.map_error(fn(msg) { RallyError("scan error: " <> msg) }),
  )

  // -- Scan & discover --
  let auth_config = detect_auth(config)
  let handler_endpoints = discover_endpoints(auth_config)
  let contracts = parse_page_contracts(routes, config.pages_root)

  let client_context_path =
    dirname(config.pages_root) <> "/client_context.gleam"
  let client_context_module = module_from_src_path(client_context_path)
  let has_client_context =
    simplifile.is_file(client_context_path) |> result.unwrap(False)
  let #(has_from_session, from_session_module) =
    resolve_from_session(config.pages_root)

  let router_module = module_from_src_path(config.output_route)
  let rpc_dispatch_module = module_from_src_path(config.output_server_dispatch)

  let route_source = generator.generate(routes)
  let dispatch_source =
    generator.generate_dispatch(
      routes,
      contracts,
      has_client_context,
      router_module,
      client_context_module,
    )

  let namespace_prefix =
    config.pages_root
    |> string.drop_start(4)
    |> fn(p) { string.replace(p, "/pages", "") }
  let ns_endpoints =
    list.filter(handler_endpoints, fn(ep) {
      string.starts_with(ep.module_path, namespace_prefix <> "/")
    })
  let sd_source =
    generate_rpc_dispatch_source(ns_endpoints, config, auth_config)

  let shell_html = case simplifile.read(config.shell_file) {
    Ok(html) -> html
    _ ->
      "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'></head>\n<body><div id='app'></div>{{rally_client_script}}</body>\n</html>"
  }

  // Walk discovered types and build push dispatch tables
  let client_context_source = case has_client_context {
    True ->
      case simplifile.read(client_context_path) {
        Ok(source) -> option.Some(source)
        _ -> option.None
      }
    False -> option.None
  }
  let discovered =
    walk_discovered_types(
      ns_endpoints,
      contracts,
      client_context_source,
      client_context_module,
    )
  let push_dispatches =
    build_push_dispatches(
      contracts,
      has_client_context,
      client_context_source,
      client_context_module,
    )
  let json_push_dispatches =
    list.map(push_dispatches, fn(d: codegen_erl.PushDispatch) {
      #(d.page_tag, d.type_atom)
    })

  let contract_hash =
    compute_contract_hash(contracts, ns_endpoints, discovered, config)

  let protocol_wire_output =
    string.replace(config.output_ws, "ws_handler.gleam", "protocol_wire.gleam")
  let protocol_wire_module =
    protocol_wire_output
    |> string.drop_start(4)
    |> string.drop_end(6)

  let ssr_source =
    ssr_handler.generate(
      contracts,
      has_client_context,
      has_from_session,
      from_session_module,
      router_module,
      shell_html,
      config.atoms_module,
      option.Some(config.wire_module),
      case has_client_context {
        True -> option.Some(client_context_module)
        False -> option.None
      },
      auth_config,
      wire_import_module: protocol_wire_module,
      protocol: config.protocol,
    )

  // Write generated files, aborting on first failure
  let result =
    do_write_files(
      config:,
      route_source:,
      dispatch_source:,
      sd_source:,
      ssr_source:,
      contracts:,
      ns_endpoints:,
      rpc_dispatch_module:,
      auth_config:,
      from_session_module:,
      protocol_wire_module:,
      contract_hash:,
    )
  use _ <- result.try(result)

  let transport_ffi_path =
    config.rally_package_path <> "/src/rally_runtime/transport_ffi.mjs"
  use transport_ffi_content <- result.try(
    simplifile.read(transport_ffi_path)
    |> result.map_error(fn(e) {
      RallyError(
        "Cannot read transport_ffi.mjs from rally package at "
        <> transport_ffi_path
        <> ": "
        <> simplifile.describe_error(e),
      )
    }),
  )

  let atoms_erl =
    generate_atoms_erl_source(
      ns_endpoints,
      discovered,
      config,
      json_push_dispatches,
    )

  use _ <- result.try(
    write_file(config.output_server_atoms, atoms_erl)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )

  let wire_erl = case
    libero.generate_wire_erl(
      discovered:,
      wire_module: config.wire_module,
      endpoints: ns_endpoints,
      push_dispatches: push_dispatches,
    )
  {
    Ok(src) -> src
    Error(err) -> {
      gen_error.print_error(err)
      ""
    }
  }
  use _ <- result.try(
    write_file(config.output_server_wire, wire_erl)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )

  let server_symbols = collect_server_symbols(ns_endpoints)

  use client_context_contract <- result.try(case client_context_source {
    option.Some(source) ->
      parser.parse_client_context(source)
      |> result.map(option.Some)
      |> result.map_error(fn(error) {
        RallyError("Cannot parse client_context.gleam: " <> error)
      })
    option.None -> Ok(option.None)
  })
  use _ <- result.try(check_json_client_context_compatibility(
    contracts,
    config.protocol,
  ))
  let raw_codec_files =
    codec.generate(
      contracts,
      discovered,
      ns_endpoints,
      server_symbols,
      config.protocol,
    )
  let codec_files =
    list.map(raw_codec_files, fn(f: codec.CodecFile) {
      client.GeneratedFile(config.client_root <> "/" <> f.path, f.content)
    })

  // Add JSON typed codecs when protocol is json
  use json_codec_files <- result.try(case config.protocol {
    "json" -> {
      let files = codec.generate_json_codecs(discovered, ns_endpoints)
      case files {
        [] ->
          Error(RallyError(
            "JSON codec generation failed - no codec files produced",
          ))
        _ -> Ok(files)
      }
    }
    _ -> Ok([])
  })
  // JSON codec files (json_codecs.gleam, json_decode_dispatch.gleam)
  // are server-only. The client uses inline encoding in types.gleam
  // and the JS facade (typedJsonToGleamValue) for decode.
  // type_registry.mjs is extracted below and written to the client package.

  // Write server-side JSON codecs alongside SSR handler when protocol is JSON
  use _ <- result.try(case config.protocol {
    "json" -> {
      case json_codec_files {
        [] -> Ok(Nil)
        [first, ..] -> {
          let server_path =
            string.replace(
              config.output_ssr,
              "ssr_handler.gleam",
              "json_codecs.gleam",
            )
          write_file(server_path, first.content)
          |> result.map_error(fn(msg) { RallyError("write error: " <> msg) })
        }
      }
    }
    _ -> Ok(Nil)
  })

  let client_files =
    client.generate_package_with_client_context_contract(
      routes,
      contracts,
      config,
      transport_ffi_content,
      client_context_contract,
      client_context_module,
      config.protocol,
    )
    |> list.append([
      client.GeneratedFile(
        config.client_root <> "/src/generated/protocol_wire.mjs",
        generator.generate_protocol_wire_js(config.protocol, contract_hash),
      ),
    ])
    |> list.append(
      list.filter_map(json_codec_files, fn(f: codec.CodecFile) {
        case f.path == "src/generated/type_registry.mjs" {
          True ->
            Ok(client.GeneratedFile(
              config.client_root <> "/src/generated/type_registry.mjs",
              f.content,
            ))
          False -> Error(Nil)
        }
      }),
    )
  let client_context_files =
    generate_client_context_files(
      config,
      client_context_path,
      client_context_module,
      server_symbols,
    )

  let layout_files = copy_layout_modules(routes:, config:, server_symbols:)

  let seed_sources =
    list.flatten([
      raw_codec_files
        |> list.filter(fn(f: codec.CodecFile) {
          string.ends_with(f.path, ".gleam")
          && string.starts_with(f.path, "src/")
          && string.contains(f.path, "/pages/")
        })
        |> list.map(fn(f: codec.CodecFile) {
          let module_path = f.path |> string.drop_start(4) |> string.drop_end(6)
          #(module_path, f.content)
        }),
      layout_files
        |> list.filter(fn(f: client.GeneratedFile) {
          string.ends_with(f.path, ".gleam")
        })
        |> list.map(fn(f: client.GeneratedFile) {
          let module_path =
            f.path
            |> string.replace(config.client_root <> "/src/", "")
            |> string.drop_end(6)
          #(module_path, f.content)
        }),
      client_context_files
        |> list.map(fn(f: client.GeneratedFile) {
          #(client_context_module, f.content)
        }),
    ])

  use dependency_files <- result.try(
    dependency_resolver.resolve(
      seed_sources:,
      src_root: source_root_for_pages(config.pages_root),
      client_root: config.client_root,
    )
    |> result.map_error(fn(msg) {
      RallyError("dependency resolution error: " <> msg)
    }),
  )

  let all_source_files =
    list.flatten([
      codec_files,
      client_files,
      client_context_files,
      layout_files,
      dependency_files,
    ])

  let gleam_toml =
    client.generate_gleam_toml(
      all_client_files: all_source_files,
      server_deps: config.server_deps,
      client_root: config.client_root,
      protocol: config.protocol,
    )

  reset_generated_client_src(config.client_root)

  use _ <- result.try(
    write_generated_files([gleam_toml, ..all_source_files])
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )

  let _dispatch_result = case simplifile.read(config.output_dispatch) {
    Ok(content) ->
      case
        !string.contains(content, "pub fn")
        && !string.contains(content, "pub type")
        && !string.contains(content, "pub const")
      {
        True -> simplifile.delete(config.output_dispatch)
        False -> Ok(Nil)
      }
    _ -> Ok(Nil)
  }

  Ok(Nil)
}

fn do_write_files(
  config config: ScanConfig,
  route_source route_source: String,
  dispatch_source dispatch_source: String,
  sd_source sd_source: String,
  ssr_source ssr_source: String,
  contracts contracts: List(#(types.ScannedRoute, types.PageContract)),
  ns_endpoints ns_endpoints: List(libero_scanner.HandlerEndpoint),
  rpc_dispatch_module rpc_dispatch_module: String,
  auth_config auth_config: option.Option(types.AuthConfig),
  from_session_module from_session_module: String,
  protocol_wire_module protocol_wire_module: String,
  contract_hash contract_hash: String,
) -> Result(Nil, RallyError) {
  let ws_source =
    ws_handler.generate(
      contracts,
      config.atoms_module,
      rpc_dispatch_module,
      auth_config,
      from_session_module:,
      endpoints: ns_endpoints,
      wire_import_module: protocol_wire_module,
      protocol: config.protocol,
    )
  use _ <- result.try(
    write_file(config.output_route, route_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(
    write_file(config.output_dispatch, dispatch_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(
    write_file(config.output_server_dispatch, sd_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(
    write_file(config.output_ssr, ssr_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(
    write_file(config.output_ws, ws_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(case ns_endpoints {
    [] -> Ok(Nil)
    _ -> {
      let http_source =
        http_handler.generate(
          ns_endpoints,
          rpc_dispatch_module,
          auth_config,
          contracts,
          from_session_module:,
          wire_import_module: protocol_wire_module,
          protocol: config.protocol,
        )
      write_file(config.output_http, http_source)
      |> result.map_error(fn(msg) { RallyError("write error: " <> msg) })
    }
  })

  // Write protocol_wire facade (Gleam)
  let protocol_wire_output =
    string.replace(config.output_ws, "ws_handler.gleam", "protocol_wire.gleam")
  let protocol_wire_source =
    generator.generate_protocol_wire(
      config.protocol,
      config.atoms_module,
      contract_hash,
      rpc_dispatch_module,
      ns_endpoints,
      auth_config,
      protocol_wire_module,
    )
  use _ <- result.try(
    write_file(protocol_wire_output, protocol_wire_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )

  Ok(Nil)
}

// ---------------------------------------------------------------------------
// Extracted phases of generate_for_config
// ---------------------------------------------------------------------------

/// Check for an auth.gleam with the required exports alongside the pages dir.
fn detect_auth(config: ScanConfig) -> option.Option(types.AuthConfig) {
  let auth_path = dirname(config.pages_root) <> "/auth.gleam"
  case simplifile.read(auth_path) {
    Ok(source) -> {
      let auth_module = module_from_src_path(auth_path)
      case
        string.contains(source, "pub type Identity")
        && string.contains(source, "pub fn resolve")
        && string.contains(source, "pub fn is_authenticated")
        && string.contains(source, "pub const redirect_url")
      {
        True -> option.Some(types.AuthConfig(auth_module:))
        False -> {
          io.println_error(
            "rally: auth.gleam found at "
            <> auth_path
            <> " but missing required exports (Identity, resolve, is_authenticated, redirect_url)",
          )
          option.None
        }
      }
    }
    _ -> option.None
  }
}

/// Scan for server_* handler endpoints via libero. When auth is configured,
/// excludes Identity params from the wire contract.
fn discover_endpoints(
  auth_config: option.Option(types.AuthConfig),
) -> List(libero_scanner.HandlerEndpoint) {
  let exclude_param_types = case auth_config {
    option.Some(types.AuthConfig(auth_module:)) -> [#(auth_module, "Identity")]
    option.None -> []
  }
  case libero.scan_excluding(exclude_param_types:) {
    Ok(endpoints) -> {
      case endpoints {
        [] -> Nil
        _ ->
          io.println(
            "rally: discovered "
            <> int.to_string(list.length(endpoints))
            <> " handler endpoints via libero",
          )
      }
      endpoints
    }
    Error(errors) -> {
      list.each(errors, gen_error.print_error)
      []
    }
  }
}

/// Read and parse each page module's source to extract its contract.
fn parse_page_contracts(
  routes: List(types.ScannedRoute),
  pages_root: String,
) -> List(#(types.ScannedRoute, types.PageContract)) {
  list.filter_map(routes, fn(route) {
    let file_path =
      pages_root <> "/" <> last_module_segment(route.module_path) <> ".gleam"
    case simplifile.read(file_path) {
      Ok(source) -> {
        case parser.parse_page(source, module_path: route.module_path) {
          Ok(contract) -> Ok(#(route, contract))
          _ -> {
            io.println_error(
              "warning: failed to parse " <> file_path <> ", skipping",
            )
            Error(Nil)
          }
        }
      }
      _ -> {
        io.println_error("warning: cannot read " <> file_path <> ", skipping")
        Error(Nil)
      }
    }
  })
}

/// Find from_session: check client_context_server.gleam first, fall back
/// to server_context.gleam.
fn resolve_from_session(pages_root: String) -> #(Bool, String) {
  let server_context_path = "src/server_context.gleam"
  let client_context_server_path =
    dirname(pages_root) <> "/client_context_server.gleam"
  let client_context_server_module =
    module_from_src_path(client_context_server_path)
  case simplifile.read(client_context_server_path) {
    Ok(source) ->
      case string.contains(source, "pub fn from_session") {
        True -> #(True, client_context_server_module)
        False -> check_server_context_from_session(server_context_path)
      }
    _ -> check_server_context_from_session(server_context_path)
  }
}

/// Generate the RPC dispatch source via libero, with auth identity threading
/// when auth is configured.
fn generate_rpc_dispatch_source(
  ns_endpoints: List(libero_scanner.HandlerEndpoint),
  config: ScanConfig,
  auth_config: option.Option(types.AuthConfig),
) -> String {
  let extra_dispatch_params = case auth_config {
    option.Some(types.AuthConfig(auth_module:)) -> {
      let auth_ref = last_segment(auth_module)
      [
        ExtraParam(
          name: "identity",
          type_ref: auth_ref <> ".Identity",
          import_line: import_as_string(auth_module, auth_ref),
        ),
      ]
    }
    option.None -> []
  }
  let source = case ns_endpoints {
    [] ->
      generator.generate_empty_rpc_dispatch(
        config.atoms_module,
        extra_dispatch_params,
      )
    _ ->
      case extra_dispatch_params {
        [] ->
          libero.generate_dispatch(
            ns_endpoints,
            option.Some(config.atoms_module),
            option.Some(config.wire_module),
          )
        params ->
          libero.generate_dispatch_with_extra_params(
            ns_endpoints,
            option.Some(config.atoms_module),
            option.Some(config.wire_module),
            params,
          )
      }
  }
  source
  |> generator.normalize_rpc_dispatch_context_import
  |> generator.normalize_rpc_dispatch_unused_fields
}

/// Collect type seeds from handlers, client context, page models, and
/// ToClient types, then walk the type graph via libero.
fn walk_discovered_types(
  ns_endpoints: List(libero_scanner.HandlerEndpoint),
  contracts: List(#(types.ScannedRoute, types.PageContract)),
  client_context_source: option.Option(String),
  client_context_module: String,
) -> List(DiscoveredType) {
  let handler_seeds = libero.collect_seeds(ns_endpoints)
  let cc_seeds = case client_context_source {
    option.Some(source) ->
      codec.client_context_seeds(source, client_context_module)
    option.None -> []
  }
  let page_model_seeds =
    list.filter_map(contracts, fn(pair) {
      let #(route, contract) = pair
      case contract.has_model {
        True -> Ok(#(route.module_path, "Model"))
        False -> Error(Nil)
      }
    })
  let to_client_seeds =
    list.filter_map(contracts, fn(pair) {
      let #(route, contract) = pair
      case has_to_client_type(route, contract) {
        True -> Ok(#(route.module_path, "ToClient"))
        False -> Error(Nil)
      }
    })
  let seeds =
    list.flatten([handler_seeds, cc_seeds, page_model_seeds, to_client_seeds])
  case libero.walk(seeds) {
    Ok(types) -> types
    Error(errors) -> {
      list.each(errors, gen_error.print_error)
      []
    }
  }
}

/// Build push dispatch entries for pages with ToClient types and for
/// ClientContextMsg when client context is present.
fn build_push_dispatches(
  contracts: List(#(types.ScannedRoute, types.PageContract)),
  has_client_context: Bool,
  client_context_source: option.Option(String),
  client_context_module: String,
) -> List(codegen_erl.PushDispatch) {
  let page_dispatches =
    list.filter_map(contracts, fn(pair) {
      let #(route, contract) = pair
      case has_to_client_type(route, contract) {
        True -> {
          let type_atom =
            libero.qualified_atom_name(
              module_path: route.module_path,
              variant_name: "ToClient",
            )
          Ok(codegen_erl.PushDispatch(
            page_tag: route.variant_name,
            type_atom: type_atom,
          ))
        }
        False -> Error(Nil)
      }
    })
  let cc_dispatch = case has_client_context, client_context_source {
    True, option.Some(_) -> {
      let type_atom =
        libero.qualified_atom_name(
          module_path: client_context_module,
          variant_name: "ClientContextMsg",
        )
      [
        codegen_erl.PushDispatch(
          page_tag: "__ClientContext__",
          type_atom: type_atom,
        ),
      ]
    }
    _, _ -> []
  }
  list.append(page_dispatches, cc_dispatch)
}

/// Compute the JSON contract hash for cache busting. Returns "" for
/// non-JSON protocols.
fn compute_contract_hash(
  contracts: List(#(types.ScannedRoute, types.PageContract)),
  ns_endpoints: List(libero_scanner.HandlerEndpoint),
  discovered: List(DiscoveredType),
  config: ScanConfig,
) -> String {
  case config.protocol {
    "json" -> {
      let push_contracts =
        list.filter_map(contracts, fn(pair) {
          let #(route, contract) = pair
          case has_to_client_type(route, contract) {
            True ->
              Ok(json_contract.PushContract(
                module: route.module_path,
                type_module: route.module_path,
                type_name: "ToClient",
              ))
            False -> Error(Nil)
          }
        })
      let ssr_model_contracts =
        list.filter_map(contracts, fn(pair) {
          let #(route, contract) = pair
          case contract.has_load && contract.has_model {
            True ->
              Ok(json_contract.SsrModelContract(
                route_module: route.module_path,
                type_module: route.module_path,
                type_name: "Model",
              ))
            False -> Error(Nil)
          }
        })
      json_contract.generate_hash(
        ns_endpoints,
        discovered,
        push_contracts,
        ssr_model_contracts,
      )
    }
    _ -> ""
  }
}

/// Generate the Erlang atoms module source. For JSON protocol, extends the
/// base module with push dispatch functions and persistent_term registrations.
fn generate_atoms_erl_source(
  ns_endpoints: List(libero_scanner.HandlerEndpoint),
  discovered: List(DiscoveredType),
  config: ScanConfig,
  json_push_dispatches: List(#(String, String)),
) -> String {
  let atoms_erl =
    libero.generate_atoms(
      ns_endpoints,
      discovered,
      config.atoms_module,
      option.Some(config.wire_module),
    )

  case config.protocol {
    "json" -> {
      let json_codec_mod =
        string.replace(config.atoms_module, "@rpc_atoms", "@json_codecs")
      let protocol_wire_mod =
        string.replace(config.atoms_module, "@rpc_atoms", "@protocol_wire")

      let push_arms = case json_push_dispatches {
        [] -> "    _Page -> error({no_json_push_encoder, Page})\n"
        _ ->
          list.map(json_push_dispatches, fn(d) {
            let #(page_tag, type_atom) = d
            "    <<\""
            <> page_tag
            <> "\">> -> '"
            <> json_codec_mod
            <> "':'json_encode_"
            <> type_atom
            <> "'(Msg);\n"
          })
          |> string.join("")
          |> fn(arms) {
            arms <> "    Page -> error({no_json_push_encoder, Page})\n"
          }
      }

      let atoms_erl =
        string.replace(
          atoms_erl,
          "-export([ensure/0]).",
          "-export([ensure/0, encode_push_frame/2, json_encode_push_value/2]).",
        )

      let atoms_erl = case
        string.split_once(
          atoms_erl,
          "persistent_term:put({?MODULE, done}, true),",
        )
      {
        Ok(#(before, after)) ->
          before
          <> "    persistent_term:put({libero, push_frame_module}, '"
          <> config.atoms_module
          <> "'),\n"
          <> "    persistent_term:put({libero, json_wire_module}, '"
          <> protocol_wire_mod
          <> "'),\n"
          <> "    persistent_term:put({?MODULE, done}, true),"
          <> after
        Error(Nil) -> atoms_erl
      }

      atoms_erl
      <> "\n\n"
      <> "%% Push dispatch: route page tag to the correct typed encoder.\n"
      <> "json_encode_push_value(Page, Msg) ->\n"
      <> "    case Page of\n"
      <> push_arms
      <> "    end.\n"
      <> "\n"
      <> "%% Single push-frame facade called by rally_runtime_ffi.\n"
      <> "encode_push_frame(Page, Msg) ->\n"
      <> "    JsonValue = json_encode_push_value(Page, Msg),\n"
      <> "    JsonWireMod = persistent_term:get({libero, json_wire_module}),\n"
      <> "    JsonWireMod:encode_push(Page, JsonValue).\n"
    }
    _ -> atoms_erl
  }
}

/// Tree-shake client_context.gleam and collect its FFI file if present.
fn generate_client_context_files(
  config: ScanConfig,
  client_context_path: String,
  client_context_module: String,
  server_symbols: List(String),
) -> List(client.GeneratedFile) {
  case simplifile.is_file(client_context_path) |> result.unwrap(False) {
    True -> {
      case simplifile.read(client_context_path) {
        Ok(cc_source) -> {
          let shaken = tree_shaker.shake(cc_source, server_symbols:)
          let ffi_path = dirname(config.pages_root) <> "/client_context_ffi.mjs"
          let ffi_files = case simplifile.read(ffi_path) {
            Ok(ffi_content) -> [
              client.GeneratedFile(
                config.client_root
                  <> "/src/"
                  <> client_context_module
                  <> "_ffi.mjs",
                ffi_content,
              ),
            ]
            _ -> []
          }
          [
            client.GeneratedFile(
              config.client_root <> "/src/" <> client_context_module <> ".gleam",
              shaken,
            ),
            ..ffi_files
          ]
        }
        _ -> []
      }
    }
    False -> []
  }
}

fn reset_generated_client_src(client_root: String) -> Nil {
  let _delete_result = simplifile.delete_all(paths: [client_root <> "/src"])
  Nil
}

fn last_module_segment(module_path: String) -> String {
  case string.split_once(module_path, "pages/") {
    Ok(#(_, rest)) -> rest
    _ -> module_path
  }
}

/// Refuse to generate a JSON-protocol client when any page references
/// `send_to_client_context`. The JSON encoding path is not implemented yet
/// (tracked in rally-au0s) and the runtime panic shim in the generated
/// `rally_runtime/effect` is a backstop, not an acceptable failure mode.
fn check_json_client_context_compatibility(
  contracts: List(#(types.ScannedRoute, types.PageContract)),
  protocol: String,
) -> Result(Nil, RallyError) {
  check_json_client_context_compatibility_result(contracts, protocol)
  |> result.map_error(RallyError)
}

/// Test-facing entry point for the JSON / client-context compatibility check.
/// Returns the rendered error message rather than the private RallyError so
/// tests can import it without touching internals.
pub fn check_json_client_context_compatibility_result(
  contracts: List(#(types.ScannedRoute, types.PageContract)),
  protocol: String,
) -> Result(Nil, String) {
  case protocol {
    "json" -> {
      let offenders =
        list.filter_map(contracts, fn(pair) {
          let #(route, contract) = pair
          case string.contains(contract.source, "send_to_client_context") {
            True -> Ok(route.module_path)
            False -> Error(Nil)
          }
        })
      case offenders {
        [] -> Ok(Nil)
        _ ->
          Error(
            "JSON protocol does not yet support client-context messages. "
            <> "These pages call send_to_client_context but the JSON encoder "
            <> "is not implemented (tracked in rally-au0s):\n  - "
            <> string.join(offenders, "\n  - ")
            <> "\nEither switch the namespace to protocol = \"etf\" or remove "
            <> "the send_to_client_context calls from these pages.",
          )
      }
    }
    _ -> Ok(Nil)
  }
}

fn write_file(path: String, content: String) -> Result(Nil, String) {
  let formatted = case string.ends_with(path, ".gleam") {
    True -> format.format_gleam(content)
    False -> content
  }
  write_if_changed(path, formatted)
}

fn write_generated_files(
  files: List(client.GeneratedFile),
) -> Result(Nil, String) {
  list.try_fold(files, Nil, fn(_, file) {
    let formatted = case string.ends_with(file.path, ".gleam") {
      True -> format.format_gleam(file.content)
      False -> file.content
    }
    write_if_changed(file.path, formatted)
  })
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

fn module_from_src_path(path: String) -> String {
  path |> string.drop_start(4) |> string.drop_end(6)
}

fn last_segment(module_path: String) -> String {
  case string.split(module_path, "/") |> list.last {
    Ok(seg) -> seg
    Error(Nil) -> module_path
  }
}

fn import_as_string(module_path: String, alias: String) -> String {
  case last_segment(module_path) == alias {
    True -> "import " <> module_path
    False -> "import " <> module_path <> " as " <> alias
  }
}

fn source_root_for_pages(pages_root: String) -> String {
  let parts = string.split(pages_root, "/")
  case split_before_pages(parts, []) {
    Ok(prefix_parts) ->
      case take_through_src(prefix_parts, []) {
        Ok(src_parts) -> string.join(src_parts, "/")
        _ -> dirname(pages_root)
      }
    _ -> dirname(pages_root)
  }
}

fn split_before_pages(
  parts: List(String),
  acc: List(String),
) -> Result(List(String), Nil) {
  case parts {
    [] -> Error(Nil)
    ["pages", ..] -> Ok(acc)
    [part, ..rest] -> split_before_pages(rest, list.append(acc, [part]))
  }
}

fn take_through_src(
  parts: List(String),
  acc: List(String),
) -> Result(List(String), Nil) {
  case parts {
    [] -> Error(Nil)
    ["src", ..] -> Ok(list.append(acc, ["src"]))
    [part, ..rest] -> take_through_src(rest, list.append(acc, [part]))
  }
}

fn copy_layout_modules(
  routes routes: List(types.ScannedRoute),
  config config: ScanConfig,
  server_symbols server_symbols: List(String),
) -> List(client.GeneratedFile) {
  routes
  |> list.filter_map(fn(route) {
    case route.layout_module {
      option.Some(layout_module) -> Ok(layout_module)
      option.None -> Error(Nil)
    }
  })
  |> list.unique
  |> list.filter_map(fn(layout_module) {
    let file_path =
      config.pages_root <> "/" <> last_module_segment(layout_module) <> ".gleam"
    case simplifile.read(file_path) {
      Ok(source) -> {
        let shaken = tree_shaker.shake(source, server_symbols:)
        let dest = config.client_root <> "/src/" <> layout_module <> ".gleam"
        Ok(client.GeneratedFile(dest, shaken))
      }
      _ -> Error(Nil)
    }
  })
}

fn check_server_context_from_session(path: String) -> #(Bool, String) {
  case simplifile.read(path) {
    Ok(source) ->
      case string.contains(source, "pub fn from_session") {
        True -> #(True, "server_context")
        False -> #(False, "server_context")
      }
    _ -> #(False, "server_context")
  }
}

fn collect_server_symbols(
  endpoints: List(libero_scanner.HandlerEndpoint),
) -> List(String) {
  let handler_type_names =
    list.filter_map(endpoints, fn(e) {
      case e.msg_type {
        option.Some(#(_module_path, name)) -> Ok(name)
        option.None -> Error(Nil)
      }
    })
  ["ServerContext", ..handler_type_names]
}

fn has_to_client_type(
  route: types.ScannedRoute,
  contract: types.PageContract,
) -> Bool {
  list.any(contract.msg_variants, fn(variant) {
    case variant.fields {
      [field] ->
        case field.type_ {
          field_type.UserType(module_path:, type_name: "ToClient", args: [])
            if module_path == route.module_path
          -> True
          _ -> False
        }
      _ -> False
    }
  })
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
