import gleam/string
import gleeunit/should
import rally/internal/tree_shaker

// -- Test: client-only page passes through unchanged --

pub fn client_only_page_test() {
  let source =
    "import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

pub type Model { Model(count: Int, name: Option(String)) }
pub type Msg { Increment }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(count: 0, name: None), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Increment -> #(Model(..model, count: model.count + 1), effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.text(\"hello\")
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // Everything should survive since there's no server code
  result |> string.contains("pub fn init()") |> should.be_true()
  result |> string.contains("pub fn update(") |> should.be_true()
  result |> string.contains("pub fn view(") |> should.be_true()
  result |> string.contains("pub type Model") |> should.be_true()
  result |> string.contains("pub type Msg") |> should.be_true()
  // Imports used by client types/functions should survive
  result |> string.contains("gleam/option") |> should.be_true()
  result |> string.contains("lustre/effect") |> should.be_true()
  result |> string.contains("lustre/element/html") |> should.be_true()
}

// -- Test: server_* function is removed --

pub fn removes_server_function_test() {
  let source =
    "import gleam/option.{type Option, None}
import server_context.{type ServerContext}

pub type Model { Model(name: Option(String)) }
pub type Msg { Got(String) }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(name: None), effect.none())
}

pub fn view(model: Model) -> Element(Msg) {
  html.text(\"hello\")
}

pub fn server_get_name(msg: ServerGetName, server_context: ServerContext) -> String {
  \"dave\"
}
"

  let result =
    tree_shaker.shake(source, server_symbols: ["ServerContext", "ServerGetName"])

  // server_get_name and its server-only import should be gone
  result |> string.contains("server_get_name") |> should.be_false()
  result |> string.contains("server_context") |> should.be_false()
  result |> string.contains("ServerGetName") |> should.be_false()
  // client code should remain
  result |> string.contains("pub fn init()") |> should.be_true()
  result |> string.contains("pub fn view(") |> should.be_true()
  result |> string.contains("gleam/option") |> should.be_true()
}

// -- Test: private helper only used by server code is excluded --

pub fn excludes_server_only_helper_test() {
  let source =
    "import gleam/option.{type Option, None}
import server_context.{type ServerContext}
import generated/sql/auth_sql

pub type Model { Model(name: String) }
pub type Msg { Got(String) }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(name: \"\"), effect.none())
}

pub fn view(model: Model) -> Element(Msg) {
  html.text(model.name)
}

fn lookup_user(db, id) {
  auth_sql.find(db, id)
}

pub fn server_get_name(msg: ServerGetName, server_context: ServerContext) -> String {
  lookup_user(server_context.db, 1)
}
"

  let result =
    tree_shaker.shake(source, server_symbols: ["ServerContext", "ServerGetName"])

  // server function and its helper should both be gone
  result |> string.contains("server_get_name") |> should.be_false()
  result |> string.contains("lookup_user") |> should.be_false()
  result |> string.contains("auth_sql") |> should.be_false()
  // client code remains
  result |> string.contains("pub fn init()") |> should.be_true()
  result |> string.contains("pub fn view(") |> should.be_true()
}

// -- Test: private helper used by client code is kept --

pub fn keeps_client_helper_test() {
  let source =
    "import lustre/element.{type Element}
import lustre/element/html

pub type Model { Model(items: List(String)) }
pub type Msg { NoOp }

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [items_table(model.items)])
}

fn items_table(items) {
  html.ul([], [])
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  result |> string.contains("fn items_table(") |> should.be_true()
  result |> string.contains("pub fn view(") |> should.be_true()
}

// -- Test: private helper used by both client and server is kept --

pub fn keeps_shared_helper_test() {
  let source =
    "import gleam/int
import server_context.{type ServerContext}

pub type Model { Model(label: String) }
pub type Msg { NoOp }

pub fn view(model: Model) -> Element(Msg) {
  html.text(format_count(42))
}

fn format_count(n) {
  int.to_string(n)
}

pub fn server_stats(msg: ServerStats, server_context: ServerContext) -> String {
  format_count(100)
}
"

  let result =
    tree_shaker.shake(source, server_symbols: ["ServerContext", "ServerStats"])

  // shared helper stays (client uses it)
  result |> string.contains("fn format_count(") |> should.be_true()
  // server function removed
  result |> string.contains("server_stats") |> should.be_false()
  result |> string.contains("server_context") |> should.be_false()
}

// -- Test: load function is removed --

pub fn removes_load_function_test() {
  let source =
    "import server_context.{type ServerContext}

pub type Model { Model(data: String) }
pub type Msg { NoOp }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(data: \"\"), effect.none())
}

pub fn load(server_context: ServerContext) -> Model {
  Model(data: \"loaded\")
}
"

  let result = tree_shaker.shake(source, server_symbols: ["ServerContext"])

  result |> string.contains("pub fn load(") |> should.be_false()
  result |> string.contains("pub fn init()") |> should.be_true()
  result |> string.contains("server_context") |> should.be_false()
}

// -- Test: handler message type is removed --

pub fn removes_handler_message_type_test() {
  let source =
    "import server_context.{type ServerContext}

pub type Model { Model }
pub type Msg { Got(String) }
pub type ServerGetName { ServerGetName(id: Int) }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model, effect.none())
}

pub fn server_get_name(msg: ServerGetName, server_context: ServerContext) -> String {
  \"dave\"
}
"

  let result =
    tree_shaker.shake(source, server_symbols: ["ServerContext", "ServerGetName"])

  result |> string.contains("pub type ServerGetName") |> should.be_false()
  result |> string.contains("pub type Model") |> should.be_true()
  result |> string.contains("pub type Msg") |> should.be_true()
}

// -- Test: transitive private helper chain from client code --

pub fn keeps_transitive_helpers_test() {
  let source =
    "pub type Model { Model }
pub type Msg { NoOp }

pub fn view(model: Model) -> Element(Msg) {
  render_header()
}

fn render_header() {
  render_logo()
}

fn render_logo() {
  html.text(\"logo\")
}

fn server_only_helper() {
  \"nope\"
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // Both helpers in the chain should be kept
  result |> string.contains("fn render_header(") |> should.be_true()
  result |> string.contains("fn render_logo(") |> should.be_true()
  // Orphaned helper should be gone (not reachable from any public fn)
  result |> string.contains("server_only_helper") |> should.be_false()
}

// -- Test: imports used via pattern matching are kept --

pub fn keeps_imports_used_in_patterns_test() {
  let source =
    "import gleam/option.{type Option, None, Some}

pub type Model { Model(name: Option(String)) }
pub type Msg { NoOp }

pub fn view(model: Model) -> Element(Msg) {
  case model.name {
    Some(n) -> html.text(n)
    None -> html.text(\"anon\")
  }
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // gleam/option should be kept because Some/None are used in patterns
  result |> string.contains("gleam/option") |> should.be_true()
}

// -- Test: constructor used ONLY in pattern (not in type or expression) --

pub fn keeps_import_used_only_in_pattern_test() {
  let source =
    "import gleam/option.{None, Some}

pub type Model { Model(count: Int) }
pub type Msg { NoOp }

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let value = get_value()
  case value {
    Some(n) -> #(Model(count: n), effect.none())
    None -> #(model, effect.none())
  }
}

fn get_value() {
  Some(42)
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // Some/None used only in patterns and expressions, not in any type annotation
  result |> string.contains("gleam/option") |> should.be_true()
  result |> string.contains("fn get_value(") |> should.be_true()
}

// -- Test: constructor used ONLY in patterns, never in expressions or types --

pub fn keeps_import_used_only_in_case_pattern_without_type_ref_test() {
  let source =
    "import gleam/option.{None, Some}

pub type Model { Model(count: Int) }
pub type Msg { NoOp }

pub fn view(model: Model) -> Element(Msg) {
  case maybe_count(model) {
    Some(n) -> html.text(int.to_string(n))
    None -> html.text(\"none\")
  }
}

fn maybe_count(model: Model) {
  model.count
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // gleam/option is needed only because Some/None appear in case patterns.
  result |> string.contains("gleam/option") |> should.be_true()
}

// -- Test: record field names do not keep same-named server-only imports --

pub fn drops_import_matching_client_record_field_test() {
  let source =
    "import password
import rally/runtime/effect as rally_effect
import server_context.{type ServerContext}

pub type Model {
  Model(email: String, password: String)
}

pub type Msg {
  UpdatedPassword(String)
  ClickedLogin
  GotLogin(Result(String, Nil))
}

pub type ServerLogin {
  ServerLogin(email: String, password: String)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedPassword(value) -> #(Model(..model, password: value), effect.none())
    ClickedLogin -> #(
      model,
      rally_effect.rpc(
        ServerLogin(email: model.email, password: model.password),
        on_response: GotLogin,
      ),
    )
    GotLogin(_) -> #(model, effect.none())
  }
}

pub fn server_login(msg: ServerLogin, server_context: ServerContext) -> Result(String, Nil) {
  case password.verify(msg.password, \"hash\") {
    True -> Ok(\"ok\")
    False -> Error(Nil)
  }
}
"

  let result =
    tree_shaker.shake(source, server_symbols: ["ServerContext", "ServerLogin"])

  result |> string.contains("import password") |> should.be_false()
  result |> string.contains("model.password") |> should.be_true()
  result |> string.contains("rally_effect.rpc") |> should.be_true()
}

// -- Test: constructor used ONLY in a case pattern, never as expression --

pub fn keeps_import_used_only_in_case_pattern_test() {
  let source =
    "import gleam/dynamic.{type Dynamic}
import gleam/result

pub type Model { Model(value: Dynamic) }
pub type Msg { NoOp }

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case result.nil(model.value) {
    Ok(_) -> #(model, effect.none())
    Error(_) -> #(model, effect.none())
  }
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // Ok/Error are builtins so they don't need imports, but result module is used
  result |> string.contains("gleam/result") |> should.be_true()
  // dynamic is used in the type
  result |> string.contains("gleam/dynamic") |> should.be_true()
}

// -- Test: imported constructor used ONLY in case pattern --

pub fn keeps_import_for_pattern_only_constructor_test() {
  let source =
    "import my_types.{type Status, Active, Inactive}

pub type Model { Model(count: Int) }
pub type Msg { NoOp }

pub fn view(model: Model, status: Status) -> Element(Msg) {
  case status {
    Active -> html.text(\"active\")
    Inactive -> html.text(\"inactive\")
  }
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // my_types should be kept - Status is in the function signature type
  result |> string.contains("my_types") |> should.be_true()
}

// -- Test: import used only via qualified module access --

pub fn keeps_qualified_module_import_test() {
  let source =
    "import gleam/int

pub type Model { Model(count: Int) }
pub type Msg { NoOp }

pub fn view(model: Model) -> Element(Msg) {
  html.text(int.to_string(model.count))
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  result |> string.contains("gleam/int") |> should.be_true()
}

// -- Test: server handler type used by client RPC call is kept --

pub fn keeps_handler_type_used_by_client_rpc_test() {
  let source =
    "import rally/runtime/effect as rally_effect
import server_context.{type ServerContext}

pub type Model { Model(name: String) }
pub type Msg { GotName(Result(String, Nil)) }
pub type ServerGetName { ServerGetName(id: Int) }

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotName(Ok(name)) -> #(Model(name:), effect.none())
    GotName(Error(_)) -> #(model, effect.none())
  }
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(name: \"\"), rally_effect.rpc(ServerGetName(id: 1), on_response: GotName))
}

pub fn server_get_name(msg: ServerGetName, server_context: ServerContext) -> Result(String, Nil) {
  Ok(\"dave\")
}
"

  let result =
    tree_shaker.shake(source, server_symbols: ["ServerContext", "ServerGetName"])

  // ServerGetName type should be KEPT because client code uses it in rpc call
  result |> string.contains("pub type ServerGetName") |> should.be_true()
  // Server function should still be removed
  result |> string.contains("server_get_name") |> should.be_false()
  result |> string.contains("server_context") |> should.be_false()
  // Client code should remain
  result |> string.contains("pub fn init()") |> should.be_true()
  result |> string.contains("rally_effect.rpc") |> should.be_true()
}

// -- Test: constants used by client code survive, unused ones are stripped --

pub fn keeps_client_referenced_constant_test() {
  let source =
    "pub type Model { Model(count: Int) }
pub type Msg { NoOp }

const items_per_page = 20
const admin_key = \"secret-token\"

pub fn view(model: Model) -> Element(Msg) {
  html.text(int.to_string(items_per_page))
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  result |> string.contains("items_per_page") |> should.be_true()
  result |> string.contains("admin_key") |> should.be_false()
}

// -- Test: constants only used by server code are stripped --

pub fn strips_server_only_constant_test() {
  let source =
    "import server_context.{type ServerContext}

pub type Model { Model }
pub type Msg { NoOp }

const db_table = \"users\"

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model, effect.none())
}

pub fn server_lookup(msg: ServerLookup, server_context: ServerContext) -> String {
  db_table
}
"

  let result =
    tree_shaker.shake(source, server_symbols: ["ServerContext", "ServerLookup"])

  result |> string.contains("db_table") |> should.be_false()
  result |> string.contains("pub fn init()") |> should.be_true()
}

pub fn drops_rpc_import_used_only_by_removed_server_functions_test() {
  let source =
    "import rally/runtime/effect as rally_effect
import server_context.{type ServerContext}

pub type Model { Model(name: String) }
pub type Msg { NoOp }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(name: \"\"), effect.none())
}

pub fn server_notify(server_context: ServerContext) -> Result(Nil, Nil) {
  let _ = rally_effect.broadcast_to_page(\"Home\", Nil)
  Ok(Nil)
}
"

  let result = tree_shaker.shake(source, server_symbols: ["ServerContext"])

  result
  |> string.contains("import rally/runtime/effect as rally_effect")
  |> should.be_false()
}

// -- Test: local variable name does not keep same-named module import --

pub fn drops_import_when_name_is_only_local_variable_test() {
  let source =
    "import gleam/result
import gleam/int

pub type Model { Model(data: String) }
pub type Msg { GotData(Result(String, Nil)) }

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let result = get_data()
  case result {
    Ok(value) -> #(Model(data: value), effect.none())
    Error(_) -> #(model, effect.none())
  }
}

fn get_data() {
  Ok(\"hello\")
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // `result` is only a local variable, not a qualified module access
  result |> string.contains("gleam/result") |> should.be_false()
  // `int` is never used (no int.something), should also be dropped
  result |> string.contains("gleam/int") |> should.be_false()
  result |> string.contains("pub fn update(") |> should.be_true()
}

// -- Test: parameter name does not keep same-named module import --

pub fn drops_import_when_name_is_only_parameter_test() {
  let source =
    "import age

pub type Model { Model(value: Int) }
pub type Msg { NoOp }

pub fn view(model: Model) -> Element(Msg) {
  html.text(format_age(age: 25))
}

fn format_age(age age: Int) -> String {
  int.to_string(age)
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // `age` is a parameter name and argument label, not age.something()
  result |> string.contains("import age") |> should.be_false()
  result |> string.contains("pub fn view(") |> should.be_true()
}

// -- Test: field access on local variable does not keep same-named module --

pub fn drops_import_when_field_access_is_on_local_variable_test() {
  let source =
    "import gleam/result

pub type DataResult { DataResult(rows: List(String), total: Int) }
pub type Model { Model(data: DataResult) }
pub type Msg { GotData(Result(DataResult, String)) }

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotData(Ok(result)) -> #(
      Model(data: result),
      effect.none(),
    )
    GotData(Error(_)) -> #(model, effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  let result = model.data
  html.text(int.to_string(result.total))
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // `result` is bound as case pattern and let variable, field access is on
  // the local variable, not qualified module access like result.unwrap(...)
  result |> string.contains("gleam/result") |> should.be_false()
  result |> string.contains("pub fn update(") |> should.be_true()
  result |> string.contains("pub fn view(") |> should.be_true()
}

// -- Test: module access in sibling clause survives binding in another clause --

pub fn keeps_import_when_module_used_in_sibling_case_clause_test() {
  let source =
    "import gleam/result

pub type DataResult { DataResult(rows: List(String), total: Int) }
pub type Model { Model(data: Option(DataResult)) }
pub type Msg {
  GotData(Result(DataResult, String))
  ApplyFilters(formdata: List(#(String, String)))
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotData(Ok(result)) -> #(
      Model(..model, data: Some(result)),
      effect.none(),
    )
    GotData(Error(_)) -> #(model, effect.none())
    ApplyFilters(formdata) -> {
      let get = fn(key) { list.key_find(formdata, key) |> result.unwrap(\"\") }
      #(model, effect.none())
    }
  }
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // `result` is bound in the GotData clause but used as a MODULE in the
  // ApplyFilters clause (result.unwrap). The import must survive.
  result |> string.contains("gleam/result") |> should.be_true()
  result |> string.contains("pub fn update(") |> should.be_true()
}

// -- Test: case-pattern binding with field access does not keep module --

pub fn drops_import_when_case_pattern_binds_and_accesses_fields_test() {
  let source =
    "import gleam/result

pub type DataResult { DataResult(rows: List(String), total: Int) }
pub type Model { Model(data: Option(DataResult)) }
pub type Msg { GotData(Result(DataResult, String)) }

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotData(Ok(result)) -> #(
      Model(data: Some(result)),
      show_count(result.total),
    )
    GotData(Error(_)) -> #(model, effect.none())
  }
}

fn show_count(n) {
  effect.none()
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // `result` is bound in a case pattern and accessed via result.total
  // in the same clause body — this is field access, not module access
  result |> string.contains("gleam/result") |> should.be_false()
  result |> string.contains("pub fn update(") |> should.be_true()
}

// -- Test: private type used only by server code is dropped --

pub fn drops_private_type_only_used_by_server_code_test() {
  let source =
    "import server_context.{type ServerContext}

pub type Model { Model(name: String) }
pub type Msg { GotData(Result(String, Nil)) }

type ServerRow {
  ServerRow(id: Int, name: String, created_at: Int)
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(name: \"\"), effect.none())
}

pub fn server_get_name(msg: ServerGetName, server_context: ServerContext) -> String {
  let row = ServerRow(id: 1, name: \"dave\", created_at: 0)
  row.name
}
"

  let result =
    tree_shaker.shake(source, server_symbols: ["ServerContext", "ServerGetName"])

  // Private type used only by removed server code should be dropped
  result |> string.contains("ServerRow") |> should.be_false()
  result |> string.contains("pub fn init()") |> should.be_true()
  result |> string.contains("pub type Model") |> should.be_true()
}

// -- Test: private type referenced by Model survives --

pub fn keeps_private_type_referenced_by_model_test() {
  let source =
    "pub type FilterState { Active Inactive }

pub type Model { Model(filter: FilterState) }
pub type Msg { ToggleFilter }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(filter: Active), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ToggleFilter -> {
      let new_filter = case model.filter {
        Active -> Inactive
        Inactive -> Active
      }
      #(Model(filter: new_filter), effect.none())
    }
  }
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // FilterState is used by Model and client code, must survive
  result |> string.contains("FilterState") |> should.be_true()
  result |> string.contains("Active") |> should.be_true()
  result |> string.contains("Inactive") |> should.be_true()
}

// -- Test: private type nested inside another private type survives --

pub fn keeps_transitive_private_type_referenced_through_model_test() {
  let source =
    "type Inner { Inner(value: Int) }
type Outer { Outer(inner: Inner) }
pub type Model { Model(data: Option(Outer)) }
pub type Msg { GotData(Result(Outer, String)) }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(data: None), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotData(Ok(outer)) -> #(Model(data: Some(outer)), effect.none())
    GotData(Error(_)) -> #(model, effect.none())
  }
}
"

  let result = tree_shaker.shake(source, server_symbols: [])

  // Outer survives because Model and Msg reference it.
  // Inner must also survive because Outer's variant field uses it,
  // even though no client code directly names Inner.
  result |> string.contains("type Outer") |> should.be_true()
  result |> string.contains("type Inner") |> should.be_true()
}
