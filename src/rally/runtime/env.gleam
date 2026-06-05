//// APP_ENV parsing and environment-dependent behavior.
//// Controls secure cookie policy and browser-side debug logging.
//// Set APP_ENV=prod in production; everything else defaults to dev.

import envoy
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type AppEnv {
  Dev
  Prod
}

pub fn app_env() -> AppEnv {
  get("APP_ENV")
  |> result.unwrap("dev")
  |> app_env_from_string
}

pub fn get(name: String) -> Result(String, Nil) {
  case envoy.get(name) {
    Ok(value) -> Ok(value)
    Error(Nil) -> get_from_dotenv(name)
  }
}

pub fn app_env_from_string(value: String) -> AppEnv {
  case string.lowercase(value) {
    "prod" | "production" -> Prod
    _ -> Dev
  }
}

pub fn app_env_name() -> String {
  case app_env() {
    Dev -> "dev"
    Prod -> "prod"
  }
}

pub fn is_dev() -> Bool {
  app_env() == Dev
}

pub fn secure_cookies() -> Bool {
  secure_cookies_for(app_env())
}

pub fn secure_cookies_for(app_env: AppEnv) -> Bool {
  app_env == Prod
}

fn get_from_dotenv(name: String) -> Result(String, Nil) {
  use contents <- result.try(
    simplifile.read(".env")
    |> result.map_error(fn(_) { Nil }),
  )

  contents
  |> string.split("\n")
  |> list.find_map(fn(raw_line) { dotenv_line_value(raw_line, name) })
}

fn dotenv_line_value(raw_line: String, name: String) -> Result(String, Nil) {
  let line = string.trim(raw_line)
  case line == "" || string.starts_with(line, "#") {
    True -> Error(Nil)
    False -> {
      let line = case string.starts_with(line, "export ") {
        True -> string.drop_start(line, 7)
        False -> line
      }
      case string.split_once(line, "=") {
        Ok(#(line_name, value)) ->
          case string.trim(line_name) == name {
            True -> Ok(clean_env_value(value))
            False -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    }
  }
}

fn clean_env_value(value: String) -> String {
  let value = string.trim(value)
  case string.starts_with(value, "\"") && string.ends_with(value, "\"") {
    True -> value |> string.drop_start(1) |> string.drop_end(1)
    False ->
      case string.starts_with(value, "'") && string.ends_with(value, "'") {
        True -> value |> string.drop_start(1) |> string.drop_end(1)
        False -> value
      }
  }
}
