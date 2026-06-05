import gleam/http/request
import gleam/http/response
import gleeunit/should
import rally/runtime/document

pub fn html_response_sets_content_type_test() {
  document.html_response("<main>ok</main>")
  |> response.get_header("content-type")
  |> should.equal(Ok("text/html; charset=utf-8"))
}

pub fn query_params_decodes_request_query_test() {
  let req =
    request.new()
    |> request.set_query([#("filter", "active"), #("page", "2")])

  document.query_params(
    req: req,
    from_values: fn(values) { values },
    empty: fn() { [] },
  )
  |> should.equal([#("filter", "active"), #("page", "2")])
}

pub fn standard_mount_selects_admin_mount_test() {
  document.standard_mount(path: "/admin/games", admin_prefix: "/admin")
  |> should.equal(document.Admin)
}

pub fn standard_mount_selects_public_mount_test() {
  document.standard_mount(path: "/games", admin_prefix: "/admin")
  |> should.equal(document.Public)
}

pub fn standard_entrypoint_uses_mount_bundle_names_test() {
  document.standard_entrypoint(document.Admin)
  |> should.equal("admin_app.mjs")

  document.standard_entrypoint(document.Public)
  |> should.equal("public_app.mjs")
}

pub fn hydration_attr_escapes_payloads_test() {
  document.hydration_attr(["one\"<&>", "two"])
  |> should.equal(" data-hydration=\"one&quot;&lt;&amp;&gt;,two\"")
}

pub fn boot_attrs_encode_and_escape_values_test() {
  document.boot_attrs([
    document.IntAttribute("auth-user-id", 7),
    document.StringAttribute("auth-email", "a\"b<c&d"),
    document.BoolAttribute("can-access-admin", True),
  ])
  |> should.equal(
    " data-auth-user-id=\"7\" data-auth-email=\"a&quot;b&lt;c&amp;d\" data-can-access-admin=\"1\"",
  )
}
