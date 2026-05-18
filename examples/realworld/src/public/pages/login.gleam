import generated/sql/auth_sql
import gleam/list
import gleam/option.{Some}
import gleam/string
import helpers/datetime
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import public/client_context.{type ClientContext, SignedIn, User}
import rally_runtime/auth
import rally_runtime/effect as rally_effect
import server_context.{type ServerContext}

// MODEL

pub type Model {
  Model(email: String, password: String, errors: List(String))
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model(email: "", password: "", errors: []), effect.none())
}

// UPDATE

pub type Msg {
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedLogin
  GotLogin(Result(#(String, String), List(String)))
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedEmail(val) -> #(Model(..model, email: val), effect.none())
    UpdatedPassword(val) -> #(Model(..model, password: val), effect.none())
    ClickedLogin -> #(
      model,
      rally_effect.rpc(
        ServerLogin(email: model.email, password: model.password),
        on_response: GotLogin,
      ),
    )
    GotLogin(Ok(#(username, image))) -> #(
      model,
      effect.batch([
        rally_effect.send_to_client_context(SignedIn(User(username:, image:))),
        rally_effect.navigate("/"),
      ]),
    )
    GotLogin(Error(errors)) -> #(Model(..model, errors:), effect.none())
  }
}

// VIEW

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("auth-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-6 offset-md-3 col-xs-12")], [
          html.h1([attr.class("text-xs-center")], [html.text("Sign in")]),
          html.p([attr.class("text-xs-center")], [
            html.a([attr.href("/register")], [
              html.text("Need an account?"),
            ]),
          ]),
          error_list(model.errors),
          html.fieldset([], [
            fieldset_input("text", "Email", model.email, UpdatedEmail),
            fieldset_input(
              "password",
              "Password",
              model.password,
              UpdatedPassword,
            ),
            html.button(
              [
                attr.class("btn btn-lg btn-primary pull-xs-right"),
                attr.type_("button"),
                event.on_click(ClickedLogin),
              ],
              [html.text("Sign in")],
            ),
          ]),
        ]),
      ]),
    ]),
  ])
}

fn error_list(errors: List(String)) -> Element(msg) {
  html.ul([attr.class("error-messages")], {
    list.map(errors, fn(e) { html.li([], [html.text(e)]) })
  })
}

fn fieldset_input(
  type_: String,
  placeholder: String,
  value: String,
  on_input_msg: fn(String) -> msg,
) -> Element(msg) {
  html.fieldset([attr.class("form-group")], [
    html.input([
      attr.class("form-control form-control-lg"),
      attr.type_(type_),
      attr.placeholder(placeholder),
      attr.value(value),
      event.on_input(on_input_msg),
    ]),
  ])
}

// SERVER

pub type ServerLogin {
  ServerLogin(email: String, password: String)
}

pub fn server_login(
  msg msg: ServerLogin,
  server_context server_context: ServerContext,
) -> Result(#(String, String), List(String)) {
  let errors = validate_login(msg.email, msg.password)
  case errors {
    [] -> {
      case
        auth_sql.find_user_by_email(db: server_context.db, email: msg.email)
      {
        Ok([user]) -> {
          case auth.verify(stored: user.password_hash, secret: msg.password) {
            True -> {
              let session_id = rally_effect.get_ws_session()
              let now = datetime.now_unix()
              let assert Ok(_) =
                auth_sql.create_session(
                  db: server_context.db,
                  session_id: Some(session_id),
                  user_id: user.id,
                  now: now,
                  expires_at: now + datetime.session_ttl_seconds,
                )
              Ok(#(user.username, user.image))
            }
            False -> Error(["Invalid email or password"])
          }
        }
        _ -> Error(["Invalid email or password"])
      }
    }
    _ -> Error(errors)
  }
}

fn validate_login(email: String, password_text: String) -> List(String) {
  let errors = []
  let errors = case string.is_empty(string.trim(email)) {
    True -> ["Email can't be blank", ..errors]
    False -> errors
  }
  case string.is_empty(string.trim(password_text)) {
    True -> ["Password can't be blank", ..errors]
    False -> errors
  }
}
