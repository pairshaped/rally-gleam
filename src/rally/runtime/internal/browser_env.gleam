//// Internal browser bootstrap helpers for generated SSR.

import rally/runtime/env

pub fn script() -> String {
  "<script>window.__APP_ENV__='" <> env.app_env_name() <> "'</script>"
}
