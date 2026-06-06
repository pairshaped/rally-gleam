import gleeunit/should
import rally/runtime/bootstrap

const project_toml = "
name = \"scoreboard_app\"
version = \"0.1.0\"

[tools.marmot]
database = \"db/scoreboard.db\"
"

pub fn config_from_toml_uses_project_conventions_test() {
  let assert Ok(config) =
    bootstrap.config_from_toml(
      toml: project_toml,
      default_port: 8080,
      port_override: Error(Nil),
      database_path_override: Error(Nil),
    )

  config.package_name |> should.equal("scoreboard_app")
  config.port |> should.equal(8080)
  config.database_path |> should.equal("db/scoreboard.db")
  config.auth_secret_env |> should.equal("SECRET_KEY_BASE")
  config.static_prefix |> should.equal("/assets/")
  config.static_root |> should.equal("priv/static")
}

pub fn config_from_toml_uses_env_overrides_test() {
  let assert Ok(config) =
    bootstrap.config_from_toml(
      toml: project_toml,
      default_port: 8080,
      port_override: Ok("9090"),
      database_path_override: Ok("tmp/dev.db"),
    )

  config.port |> should.equal(9090)
  config.database_path |> should.equal("tmp/dev.db")
}

pub fn config_from_toml_rejects_invalid_port_test() {
  bootstrap.config_from_toml(
    toml: project_toml,
    default_port: 8080,
    port_override: Ok("nope"),
    database_path_override: Error(Nil),
  )
  |> should.equal(Error(bootstrap.InvalidPort("nope")))
}
