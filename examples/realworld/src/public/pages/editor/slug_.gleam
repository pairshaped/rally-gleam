import generated/sql/articles_sql
import generated/sql/auth_sql
import generated/sql/tags_sql
import gleam/list
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
    slug: String,
    title: String,
    description: String,
    body: String,
    tag_input: String,
    tags: List(String),
    errors: List(String),
    loaded: Bool,
  )
}

pub fn init(
  _client_context: ClientContext,
  _slug: String,
) -> #(Model, Effect(Msg)) {
  #(
    Model(
      slug: "",
      title: "",
      description: "",
      body: "",
      tag_input: "",
      tags: [],
      errors: [],
      loaded: False,
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
  ClickedUpdate
  GotServerMsg(ToClient)
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
    ClickedUpdate -> #(
      model,
      rally_effect.send_to_server(UpdateArticle(
        title: model.title,
        description: model.description,
        body: model.body,
        tags: model.tags,
      )),
    )
    GotServerMsg(ArticleLoaded(title, description, body, tags)) -> #(
      Model(..model, title:, description:, body:, tags:, loaded: True),
      effect.none(),
    )
    GotServerMsg(ArticleUpdated(_slug)) -> #(
      Model(..model, errors: []),
      effect.none(),
    )
    GotServerMsg(EditorErrors(errors)) -> #(
      Model(..model, errors:),
      effect.none(),
    )
  }
}

// VIEW

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  case model.loaded {
    False ->
      html.div([attr.class("editor-page")], [
        html.div([attr.class("container page")], [
          html.text("Loading..."),
        ]),
      ])
    True ->
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
                    event.on_click(ClickedUpdate),
                  ],
                  [html.text("Update Article")],
                ),
              ]),
            ]),
          ]),
        ]),
      ])
  }
}

fn error_list(errors: List(String)) -> Element(msg) {
  html.ul([attr.class("error-messages")], {
    list.map(errors, fn(e) { html.li([], [html.text(e)]) })
  })
}

// SERVER

pub type ToServer {
  UpdateArticle(
    title: String,
    description: String,
    body: String,
    tags: List(String),
  )
}

pub type ToClient {
  ArticleLoaded(
    title: String,
    description: String,
    body: String,
    tags: List(String),
  )
  ArticleUpdated(slug: String)
  EditorErrors(errors: List(String))
}

pub type ServerModel {
  ServerModel(article_id: Int, author_id: Int)
  ServerModelEmpty
}

pub fn server_init(
  server_context: ServerContext,
  article_slug: String,
) -> #(ServerModel, Effect(ToClient)) {
  let session_id = rally_effect.get_ws_session()
  case
    auth_sql.find_user_by_session(
      db: server_context.db,
      session_id: session_id,
      now: datetime.now_unix(),
    )
  {
    Ok([user]) -> {
      case
        articles_sql.get_for_edit(db: server_context.db, slug: article_slug)
      {
        Ok([article]) -> {
          case article.author_id == user.id {
            True -> {
              let assert Ok(tag_rows) =
                tags_sql.list_by_article(
                  db: server_context.db,
                  article_id: article.id,
                )
              let tags = list.map(tag_rows, fn(row) { row.name })
              #(
                ServerModel(
                  article_id: article.id,
                  author_id: article.author_id,
                ),
                rally_effect.send_to_client(ArticleLoaded(
                  title: article.title,
                  description: article.description,
                  body: article.body,
                  tags:,
                )),
              )
            }
            False -> #(
              ServerModelEmpty,
              rally_effect.send_to_client(
                EditorErrors([
                  "You can only edit your own articles",
                ]),
              ),
            )
          }
        }
        _ -> #(
          ServerModelEmpty,
          rally_effect.send_to_client(EditorErrors(["Article not found"])),
        )
      }
    }
    _ -> #(
      ServerModelEmpty,
      rally_effect.send_to_client(
        EditorErrors([
          "You must be logged in to edit",
        ]),
      ),
    )
  }
}

pub fn server_update(
  model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  let UpdateArticle(title, description, body, tags) = msg
  case model {
    ServerModelEmpty -> #(
      ServerModelEmpty,
      rally_effect.send_to_client(EditorErrors(["No article loaded"])),
    )
    ServerModel(article_id, _author_id) -> {
      let errors = validate_article(title, body)
      case errors {
        [] -> {
          let now = datetime.now_unix()
          let new_slug =
            slug.unique_from_title_excluding(
              db: server_context.db,
              title: title,
              article_id: article_id,
            )
          let assert Ok(_) =
            articles_sql.update(
              db: server_context.db,
              slug: new_slug,
              title:,
              description:,
              body:,
              now:,
              article_id:,
            )
          let assert Ok(_) =
            tags_sql.unlink_from_article(db: server_context.db, article_id:)
          save_tags(server_context.db, article_id, tags)
          #(model, rally_effect.send_to_client(ArticleUpdated(slug: new_slug)))
        }
        _ -> #(model, rally_effect.send_to_client(EditorErrors(errors)))
      }
    }
  }
}

fn validate_article(title: String, body: String) -> List(String) {
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
  db: sqlight.Connection,
  article_id: Int,
  tags: List(String),
) -> Nil {
  list.each(tags, fn(tag) {
    let assert Ok(_) = tags_sql.create_or_ignore(db:, name: tag)
    let assert Ok([row]) = tags_sql.get_id_by_name(db:, name: tag)
    let assert Ok(_) =
      tags_sql.link_to_article(db:, article_id:, tag_id: row.id)
  })
}
