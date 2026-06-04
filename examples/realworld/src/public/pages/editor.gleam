import generated/sql/articles_sql
import generated/sql/auth_sql
import generated/sql/tags_sql
import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import helpers/datetime
import helpers/slug
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import public/client_context.{type ClientContext}
import rally/runtime/effect as rally_effect
import server_context.{type ServerContext}
import sqlight

// MODEL

pub type Model {
  Model(
    title: String,
    description: String,
    body: String,
    tag_input: String,
    tags: List(String),
    errors: List(String),
  )
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(
      title: "",
      description: "",
      body: "",
      tag_input: "",
      tags: [],
      errors: [],
    ),
    effect.none(),
  )
}

// UPDATE

pub type Msg {
  UpdatedTitle(String)
  UpdatedDescription(String)
  UpdatedBody(String)
  UpdatedTagInput(String)
  AddedTag
  RemovedTag(String)
  ClickedPublish
  GotPublish(Result(String, List(String)))
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedTitle(val) -> #(Model(..model, title: val), effect.none())
    UpdatedDescription(val) -> #(
      Model(..model, description: val),
      effect.none(),
    )
    UpdatedBody(val) -> #(Model(..model, body: val), effect.none())
    UpdatedTagInput(val) -> #(Model(..model, tag_input: val), effect.none())
    AddedTag -> {
      let tag = string.trim(model.tag_input)
      case tag == "" || list.contains(model.tags, tag) {
        True -> #(model, effect.none())
        False -> #(
          Model(..model, tags: list.append(model.tags, [tag]), tag_input: ""),
          effect.none(),
        )
      }
    }
    RemovedTag(tag) -> #(
      Model(..model, tags: list.filter(model.tags, fn(t) { t != tag })),
      effect.none(),
    )
    ClickedPublish -> #(
      model,
      rally_effect.rpc(
        ServerPublishArticle(
          title: model.title,
          description: model.description,
          body: model.body,
          tags: model.tags,
        ),
        on_response: GotPublish,
      ),
    )
    GotPublish(Ok(article_slug)) -> #(
      Model(..model, errors: []),
      rally_effect.navigate("/article/" <> article_slug),
    )
    GotPublish(Error(errors)) -> #(Model(..model, errors:), effect.none())
  }
}

// VIEW

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("editor-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-10 offset-md-1 col-xs-12")], [
          error_list(model.errors),
          html.fieldset([], [
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control form-control-lg"),
                attr.type_("text"),
                attr.placeholder("Article Title"),
                attr.value(model.title),
                event.on_input(UpdatedTitle),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control"),
                attr.type_("text"),
                attr.placeholder("What's this article about?"),
                attr.value(model.description),
                event.on_input(UpdatedDescription),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.textarea(
                [
                  attr.class("form-control"),
                  attr.attribute("rows", "8"),
                  attr.placeholder("Write your article (in markdown)"),
                  attr.value(model.body),
                  event.on_input(UpdatedBody),
                ],
                "",
              ),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control"),
                attr.type_("text"),
                attr.placeholder("Enter tags"),
                attr.value(model.tag_input),
                event.on_input(UpdatedTagInput),
              ]),
              html.div(
                [attr.class("tag-list")],
                list.map(model.tags, fn(tag) {
                  html.span([attr.class("tag-default tag-pill")], [
                    html.i(
                      [
                        attr.class("ion-close-round"),
                        event.on_click(RemovedTag(tag)),
                      ],
                      [],
                    ),
                    html.text(" " <> tag),
                  ])
                }),
              ),
            ]),
            html.button(
              [
                attr.class("btn btn-lg pull-xs-right btn-primary"),
                attr.type_("button"),
                event.on_click(ClickedPublish),
              ],
              [html.text("Publish Article")],
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

// SERVER

pub type ServerPublishArticle {
  ServerPublishArticle(
    title: String,
    description: String,
    body: String,
    tags: List(String),
  )
}

pub fn server_publish_article(
  msg msg: ServerPublishArticle,
  server_context server_context: ServerContext,
) -> Result(String, List(String)) {
  let errors = validate_article(title: msg.title, body: msg.body)
  use <- bool.guard(when: errors != [], return: Error(errors))

  let session_id = rally_effect.get_ws_session()
  case
    auth_sql.find_user_by_session(
      db: server_context.db,
      session_id: session_id,
      now: datetime.now_unix(),
    )
  {
    Ok([user]) -> {
      let now = datetime.now_unix()
      let article_slug =
        slug.unique_from_title(db: server_context.db, title: msg.title)
      case
        articles_sql.create(
          db: server_context.db,
          slug: article_slug,
          title: msg.title,
          description: msg.description,
          body: msg.body,
          author_id: user.id,
          created_at: now,
          updated_at: now,
        )
      {
        Ok([row]) -> {
          use Nil <- result.try(save_tags(
            db: server_context.db,
            article_id: row.id,
            tags: msg.tags,
          ))
          Ok(row.slug)
        }
        _ -> Error(["Failed to create article"])
      }
    }
    _ -> Error(["You must be logged in to publish"])
  }
}

fn validate_article(title title: String, body body: String) -> List(String) {
  let errors = []
  let errors = case string.is_empty(string.trim(title)) {
    True -> ["Title can't be blank", ..errors]
    False -> errors
  }
  case string.is_empty(string.trim(body)) {
    True -> ["Body can't be blank", ..errors]
    False -> errors
  }
}

fn save_tags(
  db db: sqlight.Connection,
  article_id article_id: Int,
  tags tags: List(String),
) -> Result(Nil, List(String)) {
  case tags {
    [] -> Ok(Nil)
    [tag, ..rest] -> {
      use Nil <- result.try(save_tag(db: db, article_id: article_id, tag: tag))
      save_tags(db: db, article_id: article_id, tags: rest)
    }
  }
}

fn save_tag(
  db db: sqlight.Connection,
  article_id article_id: Int,
  tag tag: String,
) -> Result(Nil, List(String)) {
  use _created <- result.try(
    tags_sql.create_or_ignore(db: db, name: tag)
    |> tag_sql_result_to_app_error,
  )
  use row <- result.try(case tags_sql.get_id_by_name(db: db, name: tag) {
    Ok([row]) -> Ok(row)
    _ -> Error(["Failed to save tags"])
  })
  case
    tags_sql.link_to_article(db: db, article_id: article_id, tag_id: row.id)
  {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(["Failed to save tags"])
  }
}

fn tag_sql_result_to_app_error(
  result result: Result(a, b),
) -> Result(a, List(String)) {
  case result {
    Ok(value) -> Ok(value)
    Error(_) -> Error(["Failed to save tags"])
  }
}
