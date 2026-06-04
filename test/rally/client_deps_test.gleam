import gleam/dict
import gleam/string
import gleeunit/should
import rally/internal/generator/client
import tom

fn dep(version: String) -> tom.Toml {
  tom.String(version)
}

fn local_dep(path: String) -> tom.Toml {
  tom.InlineTable(dict.from_list([#("path", tom.String(path))]))
}

pub fn includes_dep_when_client_source_imports_it_test() {
  let files = [
    client.GeneratedFile(
      "test_client/src/pages/notices.gleam",
      "import gleam/time/timestamp\nimport gleam/time/calendar\npub type Model { Model }\n",
    ),
  ]
  let server_deps =
    dict.from_list([
      #("gleam_time", dep(">= 1.7.0 and < 2.0.0")),
      #("gleam_json", dep(">= 3.0.0 and < 4.0.0")),
    ])
  let result =
    client.generate_gleam_toml(
      all_client_files: files,
      server_deps: server_deps,
      client_root: "test_client",
      protocol: "etf",
    )

  result.content |> string.contains("gleam_time") |> should.be_true()
  result.content |> string.contains("gleam_json") |> should.be_false()
}

pub fn excludes_unused_server_deps_test() {
  let files = [
    client.GeneratedFile(
      "test_client/src/pages/home.gleam",
      "import lustre/element\npub type Model { Model }\n",
    ),
  ]
  let server_deps =
    dict.from_list([
      #("gleam_time", dep(">= 1.7.0 and < 2.0.0")),
      #("gleam_http", dep(">= 4.0.0 and < 5.0.0")),
      #("bucket", dep(">= 1.0.0 and < 2.0.0")),
    ])
  let result =
    client.generate_gleam_toml(
      all_client_files: files,
      server_deps: server_deps,
      client_root: "test_client",
      protocol: "etf",
    )

  result.content |> string.contains("gleam_time") |> should.be_false()
  result.content |> string.contains("gleam_http") |> should.be_false()
  result.content |> string.contains("bucket") |> should.be_false()
}

pub fn excludes_browser_impossible_deps_even_if_imported_test() {
  let files = [
    client.GeneratedFile(
      "test_client/src/pages/data.gleam",
      "import sqlight\npub type Model { Model }\n",
    ),
  ]
  let server_deps = dict.from_list([#("sqlight", dep(">= 0.5.0 and < 1.0.0"))])
  let result =
    client.generate_gleam_toml(
      all_client_files: files,
      server_deps: server_deps,
      client_root: "test_client",
      protocol: "etf",
    )

  result.content |> string.contains("sqlight") |> should.be_false()
}

pub fn generated_client_keeps_lustre_5_bound_test() {
  let result =
    client.generate_gleam_toml(
      all_client_files: [],
      server_deps: dict.new(),
      client_root: "test_client",
      protocol: "etf",
    )

  result.content
  |> string.contains("lustre = \">= 5.7.0 and < 6.0.0\"")
  |> should.be_true()
}

pub fn includes_json_protocol_deps_test() {
  let files = [
    client.GeneratedFile(
      "test_client/src/pages/home.gleam",
      "pub type Model { Model }\n",
    ),
  ]
  let server_deps =
    dict.from_list([
      #("gleam_json", dep(">= 3.0.0 and < 4.0.0")),
      #("libero", local_dep("../../gleam/libero")),
    ])
  let result =
    client.generate_gleam_toml(
      all_client_files: files,
      server_deps: server_deps,
      client_root: "test_client",
      protocol: "json",
    )

  result.content |> string.contains("gleam_json") |> should.be_true()
  result.content |> string.contains("libero") |> should.be_true()
}

pub fn includes_local_path_dep_when_imported_test() {
  let files = [
    client.GeneratedFile(
      "test_client/src/pages/theme.gleam",
      "import glaze/basecoat/button\npub type Model { Model }\n",
    ),
  ]
  let server_deps =
    dict.from_list([
      #("glaze_basecoat", local_dep("lib/glaze/glaze_basecoat")),
    ])
  let result =
    client.generate_gleam_toml(
      all_client_files: files,
      server_deps: server_deps,
      client_root: "test_client",
      protocol: "etf",
    )

  result.content |> string.contains("glaze_basecoat") |> should.be_true()
}

pub fn only_scans_gleam_files_test() {
  let files = [
    client.GeneratedFile(
      "test_client/src/transport_ffi.mjs",
      "import gleam/time/timestamp\n",
    ),
  ]
  let server_deps =
    dict.from_list([#("gleam_time", dep(">= 1.7.0 and < 2.0.0"))])
  let result =
    client.generate_gleam_toml(
      all_client_files: files,
      server_deps: server_deps,
      client_root: "test_client",
      protocol: "etf",
    )

  result.content |> string.contains("gleam_time") |> should.be_false()
}
