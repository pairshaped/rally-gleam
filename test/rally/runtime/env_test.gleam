import gleeunit/should
import rally/runtime/env

pub fn app_env_from_string_defaults_to_dev_test() {
  env.app_env_from_string("")
  |> should.equal(env.Dev)

  env.app_env_from_string("banana")
  |> should.equal(env.Dev)
}

pub fn app_env_from_string_accepts_prod_aliases_test() {
  env.app_env_from_string("prod")
  |> should.equal(env.Prod)

  env.app_env_from_string("production")
  |> should.equal(env.Prod)
}

pub fn secure_cookies_only_in_prod_test() {
  env.secure_cookies_for(env.Dev)
  |> should.equal(False)

  env.secure_cookies_for(env.Prod)
  |> should.equal(True)
}
