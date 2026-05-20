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
import rally/runtime/auth
import rally/runtime/effect as rally_effect
import server_context.{type ServerContext}

// MODEL

pub type Model {
  Model(username: String, email: String, password: String, errors: List(String))
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model(username: "", email: "", password: "", errors: []), effect.none())
}

// UPDATE

pub type Msg {
  UpdatedUsername(String)
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedRegister
  GotRegister(Result(#(String, String), List(String)))
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedUsername(val) -> #(Model(..model, username: val), effect.none())
    UpdatedEmail(val) -> #(Model(..model, email: val), effect.none())
    UpdatedPassword(val) -> #(Model(..model, password: val), effect.none())
    ClickedRegister -> #(
      model,
      rally_effect.rpc(
        ServerRegister(
          username: model.username,
          email: model.email,
          password: model.password,
        ),
        on_response: GotRegister,
      ),
    )
    GotRegister(Ok(#(username, image))) -> #(
      model,
      effect.batch([
        rally_effect.send_to_client_context(SignedIn(User(username:, image:))),
        rally_effect.navigate("/"),
      ]),
    )
    GotRegister(Error(errors)) -> #(Model(..model, errors:), effect.none())
  }
}

// VIEW

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("auth-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-6 offset-md-3 col-xs-12")], [
          html.h1([attr.class("text-xs-center")], [html.text("Sign up")]),
          html.p([attr.class("text-xs-center")], [
            html.a([attr.href("/login")], [html.text("Have an account?")]),
          ]),
          error_list(model.errors),
          html.fieldset([], [
            fieldset_input("text", "Your Name", model.username, UpdatedUsername),
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
                event.on_click(ClickedRegister),
              ],
              [html.text("Sign up")],
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

pub type ServerRegister {
  ServerRegister(username: String, email: String, password: String)
}

pub fn server_register(
  msg msg: ServerRegister,
  server_context server_context: ServerContext,
) -> Result(#(String, String), List(String)) {
  let errors = validate_register(msg.username, msg.email, msg.password)
  case errors {
    [] -> {
      let session_id = rally_effect.get_ws_session()
      let now = datetime.now_unix()
      let hash = auth.hash(secret: msg.password)
      case
        auth_sql.register_user(
          db: server_context.db,
          username: msg.username,
          email: msg.email,
          password_hash: hash,
          bio: "",
          image: "",
          created_at: now,
          updated_at: now,
        )
      {
        Ok([user]) -> {
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
        _ -> Error(["Username or email already taken"])
      }
    }
    _ -> Error(errors)
  }
}

fn validate_register(
  username: String,
  email: String,
  password_text: String,
) -> List(String) {
  let errors = []
  let errors = case string.is_empty(string.trim(username)) {
    True -> ["Username can't be blank", ..errors]
    False -> errors
  }
  let errors = case string.is_empty(string.trim(email)) {
    True -> ["Email can't be blank", ..errors]
    False -> errors
  }
  case string.length(password_text) < 8 {
    True -> ["Password must be at least 8 characters", ..errors]
    False -> errors
  }
}
