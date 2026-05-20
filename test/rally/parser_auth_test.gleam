import rally/internal/parser

pub fn parse_page_auth_required_test() {
  let source =
    "
import rally/runtime/auth

pub const page_auth = auth.Required

pub type Model { Model }
pub type Msg { NoOp }
pub fn load(server_context) { Nil }
pub fn init_loaded(ctx, data) { #(Model, []) }
pub fn view(ctx, model) { element.none() }
pub fn update(ctx, model, msg) { #(model, []) }
"
  let assert Ok(contract) = parser.parse_page(source:, module_path: "test/page")
  let assert True = contract.has_page_auth
  let assert True = contract.page_auth_required
  let assert False = contract.has_authorize
}

pub fn parse_page_auth_optional_test() {
  let source =
    "
import rally/runtime/auth

pub const page_auth = auth.Optional

pub type Model { Model }
pub type Msg { NoOp }
pub fn load(server_context) { Nil }
pub fn init_loaded(ctx, data) { #(Model, []) }
pub fn view(ctx, model) { element.none() }
pub fn update(ctx, model, msg) { #(model, []) }
"
  let assert Ok(contract) = parser.parse_page(source:, module_path: "test/page")
  let assert True = contract.has_page_auth
  let assert False = contract.page_auth_required
}

pub fn parse_page_no_auth_test() {
  let source =
    "
pub type Model { Model }
pub type Msg { NoOp }
pub fn load(server_context) { Nil }
pub fn init_loaded(ctx, data) { #(Model, []) }
pub fn view(ctx, model) { element.none() }
pub fn update(ctx, model, msg) { #(model, []) }
"
  let assert Ok(contract) = parser.parse_page(source:, module_path: "test/page")
  let assert False = contract.has_page_auth
  let assert False = contract.page_auth_required
}

pub fn parse_authorize_test() {
  let source =
    "
import rally/runtime/auth

pub const page_auth = auth.Required

pub fn authorize(server_context, identity) { True }

pub type Model { Model }
pub type Msg { NoOp }
pub fn load(server_context) { Nil }
pub fn init_loaded(ctx, data) { #(Model, []) }
pub fn view(ctx, model) { element.none() }
pub fn update(ctx, model, msg) { #(model, []) }
"
  let assert Ok(contract) = parser.parse_page(source:, module_path: "test/page")
  let assert True = contract.has_page_auth
  let assert True = contract.page_auth_required
  let assert True = contract.has_authorize
}
