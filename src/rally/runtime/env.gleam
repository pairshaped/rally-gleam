//// APP_ENV parsing and environment-dependent behavior.
//// Controls secure cookie policy and browser-side debug logging.
//// Set APP_ENV=prod in production; everything else defaults to dev.

import envoy
import gleam/result
import gleam/string

pub type AppEnv {
  Dev
  Prod
}

pub fn app_env() -> AppEnv {
  envoy.get("APP_ENV")
  |> result.unwrap("dev")
  |> app_env_from_string
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
