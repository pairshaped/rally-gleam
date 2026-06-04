import generated/sql/auth_sql
import gleam/bool
import gleam/list
import gleam/string
import helpers/datetime
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import public/client_context.{type ClientContext, SignedIn, SignedOut, User}
import rally/runtime/auth
import rally/runtime/effect as rally_effect
import server_context.{type ServerContext}
import sqlight

// MODEL

pub type Model {
  Model(
    image: String,
    username: String,
    bio: String,
    email: String,
    password: String,
    errors: List(String),
  )
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(image: "", username: "", bio: "", email: "", password: "", errors: []),
    effect.none(),
  )
}

// UPDATE

pub type Msg {
  UpdatedImage(String)
  UpdatedUsername(String)
  UpdatedBio(String)
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedUpdate
  ClickedLogout
  GotUpdate(Result(#(String, String), List(String)))
  GotLogout(Result(Nil, Nil))
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedImage(val) -> #(Model(..model, image: val), effect.none())
    UpdatedUsername(val) -> #(Model(..model, username: val), effect.none())
    UpdatedBio(val) -> #(Model(..model, bio: val), effect.none())
    UpdatedEmail(val) -> #(Model(..model, email: val), effect.none())
    UpdatedPassword(val) -> #(Model(..model, password: val), effect.none())
    ClickedUpdate -> #(
      model,
      rally_effect.rpc(
        ServerUpdateSettings(
          image: model.image,
          username: model.username,
          bio: model.bio,
          email: model.email,
          password: model.password,
        ),
        on_response: GotUpdate,
      ),
    )
    ClickedLogout -> #(
      model,
      rally_effect.rpc(ServerLogout, on_response: GotLogout),
    )
    GotUpdate(Ok(#(username, image))) -> #(
      Model(..model, errors: []),
      rally_effect.send_to_client_context(SignedIn(User(username:, image:))),
    )
    GotUpdate(Error(errors)) -> #(Model(..model, errors:), effect.none())
    GotLogout(Ok(_)) -> #(
      model,
      effect.batch([
        rally_effect.send_to_client_context(SignedOut),
        rally_effect.navigate("/"),
      ]),
    )
    GotLogout(Error(_error)) -> #(model, effect.none())
  }
}

// VIEW

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("settings-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-6 offset-md-3 col-xs-12")], [
          html.h1([attr.class("text-xs-center")], [html.text("Your Settings")]),
          error_list(model.errors),
          html.fieldset([], [
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control"),
                attr.type_("text"),
                attr.placeholder("URL of profile picture"),
                attr.value(model.image),
                event.on_input(UpdatedImage),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control form-control-lg"),
                attr.type_("text"),
                attr.placeholder("Your Name"),
                attr.value(model.username),
                event.on_input(UpdatedUsername),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.textarea(
                [
                  attr.class("form-control form-control-lg"),
                  attr.attribute("rows", "8"),
                  attr.placeholder("Short bio about you"),
                  attr.value(model.bio),
                  event.on_input(UpdatedBio),
                ],
                "",
              ),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control form-control-lg"),
                attr.type_("text"),
                attr.placeholder("Email"),
                attr.value(model.email),
                event.on_input(UpdatedEmail),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control form-control-lg"),
                attr.type_("password"),
                attr.placeholder("New Password"),
                attr.value(model.password),
                event.on_input(UpdatedPassword),
              ]),
            ]),
            html.button(
              [
                attr.class("btn btn-lg btn-primary pull-xs-right"),
                attr.type_("button"),
                event.on_click(ClickedUpdate),
              ],
              [html.text("Update Settings")],
            ),
          ]),
          html.hr([]),
          html.button(
            [
              attr.class("btn btn-outline-danger"),
              attr.type_("button"),
              event.on_click(ClickedLogout),
            ],
            [html.text("Or click here to logout.")],
          ),
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

// SERVER

pub type ServerUpdateSettings {
  ServerUpdateSettings(
    image: String,
    username: String,
    bio: String,
    email: String,
    password: String,
  )
}

pub type ServerLogout {
  ServerLogout
}

pub fn server_update_settings(
  msg msg: ServerUpdateSettings,
  server_context server_context: ServerContext,
) -> Result(#(String, String), List(String)) {
  let session_id = rally_effect.get_ws_session()
  case
    auth_sql.find_user_by_session(
      db: server_context.db,
      session_id: session_id,
      now: datetime.now_unix(),
    )
  {
    Ok([user]) -> {
      let errors = validate_settings(username: msg.username, email: msg.email)
      use <- bool.guard(when: errors != [], return: Error(errors))
      update_user_settings(
        msg: msg,
        user_id: user.id,
        now: datetime.now_unix(),
        db: server_context.db,
      )
    }
    _ -> Error(["You must be logged in"])
  }
}

pub fn server_logout(
  msg _msg: ServerLogout,
  server_context server_context: ServerContext,
) -> Result(Nil, Nil) {
  let session_id = rally_effect.get_ws_session()
  case auth_sql.delete_session(db: server_context.db, session_id: session_id) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}

fn update_user_settings(
  msg msg: ServerUpdateSettings,
  user_id user_id: Int,
  now now: Int,
  db db: sqlight.Connection,
) -> Result(#(String, String), List(String)) {
  case string.is_empty(string.trim(msg.password)) {
    True ->
      auth_sql.update_user(
        db: db,
        image: msg.image,
        username: msg.username,
        bio: msg.bio,
        email: msg.email,
        now:,
        user_id:,
      )
      |> result_to_settings_response(
        result: _,
        username: msg.username,
        image: msg.image,
      )
    False -> {
      case string.length(msg.password) < 8 {
        True -> Error(["Password must be at least 8 characters"])
        False ->
          auth_sql.update_user_with_password(
            db: db,
            image: msg.image,
            username: msg.username,
            bio: msg.bio,
            email: msg.email,
            password_hash: auth.hash(secret: msg.password),
            now:,
            user_id:,
          )
          |> result_to_settings_response(
            result: _,
            username: msg.username,
            image: msg.image,
          )
      }
    }
  }
}

fn result_to_settings_response(
  result result: Result(a, b),
  username username: String,
  image image: String,
) -> Result(#(String, String), List(String)) {
  case result {
    Ok(_) -> Ok(#(username, image))
    Error(_) -> Error(["Username or email already taken"])
  }
}

fn validate_settings(
  username username: String,
  email email: String,
) -> List(String) {
  let errors = []
  let errors = case string.is_empty(string.trim(username)) {
    True -> ["Username can't be blank", ..errors]
    False -> errors
  }
  case string.is_empty(string.trim(email)) {
    True -> ["Email can't be blank", ..errors]
    False -> errors
  }
}
