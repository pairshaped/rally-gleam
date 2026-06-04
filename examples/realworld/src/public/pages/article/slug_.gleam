import generated/sql/articles_sql
import generated/sql/auth_sql
import generated/sql/comments_sql
import generated/sql/favorites_sql
import generated/sql/follows_sql
import generated/sql/tags_sql
import generated/sql/users_sql
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import helpers/datetime
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
    article: Option(Article),
    comments: List(Comment),
    is_favorited: Bool,
    is_following: Bool,
    favorites_count: Int,
    comment_body: String,
    errors: List(String),
  )
}

pub type Article {
  Article(
    id: Int,
    slug: String,
    title: String,
    description: String,
    body: String,
    created_at: Int,
    tags: List(String),
    author_username: String,
    author_image: String,
    author_bio: String,
  )
}

pub type Comment {
  Comment(
    id: Int,
    body: String,
    created_at: Int,
    username: String,
    image: String,
  )
}

pub fn init(
  client_context _client_context: ClientContext,
  slug _slug: String,
) -> #(Model, Effect(Msg)) {
  #(
    Model(
      article: None,
      comments: [],
      is_favorited: False,
      is_following: False,
      favorites_count: 0,
      comment_body: "",
      errors: [],
    ),
    effect.none(),
  )
}

// UPDATE

pub type Msg {
  ClickedFavorite
  ClickedFollow(String)
  UpdatedComment(String)
  ClickedSubmitComment
  ClickedDeleteComment(Int)
  ClickedDeleteArticle
  GotServerMsg(ToClient)
}

pub fn update(
  client_context _client_context: ClientContext,
  model model: Model,
  msg msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    ClickedFavorite -> #(model, rally_effect.send_to_server(ToggleFavorite))
    ClickedFollow(username) -> #(
      model,
      rally_effect.send_to_server(ToggleFollow(username:)),
    )
    UpdatedComment(val) -> #(Model(..model, comment_body: val), effect.none())
    ClickedSubmitComment -> #(
      Model(..model, comment_body: ""),
      rally_effect.send_to_server(SubmitComment(body: model.comment_body)),
    )
    ClickedDeleteComment(id) -> #(
      model,
      rally_effect.send_to_server(DeleteComment(id:)),
    )
    ClickedDeleteArticle -> #(model, rally_effect.send_to_server(DeleteArticle))
    GotServerMsg(ArticleData(
      article,
      comments,
      is_favorited,
      is_following,
      favorites_count,
    )) -> #(
      Model(
        ..model,
        article: Some(article),
        comments:,
        is_favorited:,
        is_following:,
        favorites_count:,
      ),
      effect.none(),
    )
    GotServerMsg(FavoriteUpdated(count, is_favorited)) -> #(
      Model(..model, favorites_count: count, is_favorited:),
      effect.none(),
    )
    GotServerMsg(FavoriteCountUpdated(count)) -> #(
      Model(..model, favorites_count: count),
      effect.none(),
    )
    GotServerMsg(FollowUpdated(is_following)) -> #(
      Model(..model, is_following:),
      effect.none(),
    )
    GotServerMsg(CommentAdded(comment)) -> #(
      Model(..model, comments: list.append(model.comments, [comment])),
      effect.none(),
    )
    GotServerMsg(CommentRemoved(id)) -> #(
      Model(
        ..model,
        comments: list.filter(model.comments, fn(c) { c.id != id }),
      ),
      effect.none(),
    )
    GotServerMsg(ArticleDeleted) -> #(model, effect.none())
    GotServerMsg(ArticleError(err)) -> #(
      Model(..model, errors: [err]),
      effect.none(),
    )
  }
}

// VIEW

pub fn view(
  client_context client_context: ClientContext,
  model model: Model,
) -> Element(Msg) {
  case model.article {
    None ->
      html.div([attr.class("article-page")], [
        html.div([attr.class("container page")], [
          html.text("Loading..."),
        ]),
      ])
    Some(article) ->
      html.div([attr.class("article-page")], [
        article_banner(
          article:,
          is_favorited: model.is_favorited,
          is_following: model.is_following,
          favorites_count: model.favorites_count,
        ),
        html.div([attr.class("container page")], [
          html.div([attr.class("row article-content")], [
            html.div([attr.class("col-md-12")], [
              html.p([], [html.text(article.body)]),
              html.ul(
                [attr.class("tag-list")],
                list.map(article.tags, fn(tag) {
                  html.li([attr.class("tag-default tag-pill tag-outline")], [
                    html.text(tag),
                  ])
                }),
              ),
            ]),
          ]),
          html.hr([]),
          html.div([attr.class("article-actions")], [
            article_meta(
              article:,
              is_favorited: model.is_favorited,
              is_following: model.is_following,
              favorites_count: model.favorites_count,
            ),
          ]),
          comment_section(client_context: client_context, model: model),
        ]),
      ])
  }
}

fn article_banner(
  article article: Article,
  is_favorited is_favorited: Bool,
  is_following is_following: Bool,
  favorites_count favorites_count: Int,
) -> Element(Msg) {
  html.div([attr.class("banner")], [
    html.div([attr.class("container")], [
      html.h1([], [html.text(article.title)]),
      article_meta(article:, is_favorited:, is_following:, favorites_count:),
    ]),
  ])
}

fn article_meta(
  article article: Article,
  is_favorited is_favorited: Bool,
  is_following is_following: Bool,
  favorites_count favorites_count: Int,
) -> Element(Msg) {
  let follow_class = case is_following {
    True -> "btn btn-sm btn-secondary"
    False -> "btn btn-sm btn-outline-secondary"
  }
  let follow_text = case is_following {
    True -> "Unfollow " <> article.author_username
    False -> "Follow " <> article.author_username
  }
  let fav_class = case is_favorited {
    True -> "btn btn-sm btn-primary"
    False -> "btn btn-sm btn-outline-primary"
  }
  let fav_text = case is_favorited {
    True -> "Unfavorite Article (" <> int.to_string(favorites_count) <> ")"
    False -> "Favorite Article (" <> int.to_string(favorites_count) <> ")"
  }
  html.div([attr.class("article-meta")], [
    html.a([attr.href("/profile/" <> article.author_username)], [
      html.img([attr.src(article.author_image)]),
    ]),
    html.div([attr.class("info")], [
      html.a(
        [
          attr.class("author"),
          attr.href("/profile/" <> article.author_username),
        ],
        [html.text(article.author_username)],
      ),
      html.span([attr.class("date")], [
        html.text(int.to_string(article.created_at)),
      ]),
    ]),
    html.button(
      [
        attr.class(follow_class),
        event.on_click(ClickedFollow(article.author_username)),
      ],
      [
        html.i([attr.class("ion-plus-round")], []),
        html.text(" " <> follow_text),
      ],
    ),
    html.text(" "),
    html.button([attr.class(fav_class), event.on_click(ClickedFavorite)], [
      html.i([attr.class("ion-heart")], []),
      html.text(" " <> fav_text),
    ]),
  ])
}

fn comment_section(
  client_context client_context: ClientContext,
  model model: Model,
) -> Element(Msg) {
  html.div([attr.class("row")], [
    html.div(
      [attr.class("col-xs-12 col-md-8 offset-md-2")],
      list.flatten([
        case client_context.current_user {
          Some(_user) -> [comment_form(model.comment_body)]
          None -> []
        },
        list.map(model.comments, comment_card),
      ]),
    ),
  ])
}

fn comment_form(comment_body: String) -> Element(Msg) {
  html.form([attr.class("card comment-form")], [
    html.div([attr.class("card-block")], [
      html.textarea(
        [
          attr.class("form-control"),
          attr.placeholder("Write a comment..."),
          attr.attribute("rows", "3"),
          attr.value(comment_body),
          event.on_input(UpdatedComment),
        ],
        "",
      ),
    ]),
    html.div([attr.class("card-footer")], [
      html.button(
        [
          attr.class("btn btn-sm btn-primary"),
          attr.type_("button"),
          event.on_click(ClickedSubmitComment),
        ],
        [html.text("Post Comment")],
      ),
    ]),
  ])
}

fn comment_card(comment: Comment) -> Element(Msg) {
  html.div([attr.class("card")], [
    html.div([attr.class("card-block")], [
      html.p([attr.class("card-text")], [html.text(comment.body)]),
    ]),
    html.div([attr.class("card-footer")], [
      html.a(
        [
          attr.class("comment-author"),
          attr.href("/profile/" <> comment.username),
        ],
        [html.img([attr.class("comment-author-img"), attr.src(comment.image)])],
      ),
      html.text(" "),
      html.a(
        [
          attr.class("comment-author"),
          attr.href("/profile/" <> comment.username),
        ],
        [html.text(comment.username)],
      ),
      html.span([attr.class("date-posted")], [
        html.text(int.to_string(comment.created_at)),
      ]),
      html.span([attr.class("mod-options")], [
        html.i(
          [
            attr.class("ion-trash-a"),
            event.on_click(ClickedDeleteComment(comment.id)),
          ],
          [],
        ),
      ]),
    ]),
  ])
}

// SERVER

pub type ToServer {
  ToggleFavorite
  ToggleFollow(username: String)
  SubmitComment(body: String)
  DeleteComment(id: Int)
  DeleteArticle
}

pub type ToClient {
  ArticleData(
    article: Article,
    comments: List(Comment),
    is_favorited: Bool,
    is_following: Bool,
    favorites_count: Int,
  )
  FavoriteUpdated(count: Int, is_favorited: Bool)
  FavoriteCountUpdated(count: Int)
  FollowUpdated(is_following: Bool)
  CommentAdded(Comment)
  CommentRemoved(id: Int)
  ArticleDeleted
  ArticleError(String)
}

pub type ServerModel {
  ServerModel(article_id: Int, author_id: Int)
  ServerModelEmpty
}

type ServerError {
  ServerError(message: String)
}

pub fn server_init(
  server_context server_context: ServerContext,
  article_slug article_slug: String,
) -> #(ServerModel, Effect(ToClient)) {
  let session_id = rally_effect.get_ws_session()
  case get_current_user_id(db: server_context.db, session_id:) {
    Ok(maybe_user_id) ->
      case
        load_article_page(db: server_context.db, article_slug:, maybe_user_id:)
      {
        Ok(#(model, message)) -> #(model, rally_effect.send_to_client(message))
        Error(error) -> #(
          ServerModelEmpty,
          rally_effect.send_to_client(ArticleError(error_message(error:))),
        )
      }
    Error(error) -> #(
      ServerModelEmpty,
      rally_effect.send_to_client(ArticleError(error_message(error:))),
    )
  }
}

pub fn server_update(
  model model: ServerModel,
  msg msg: ToServer,
  server_context server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    ToggleFavorite -> update_favorite(model: model, db: server_context.db)
    ToggleFollow(username) ->
      update_follow(model: model, db: server_context.db, username:)
    SubmitComment(body) ->
      submit_comment(model: model, db: server_context.db, body:)
    DeleteComment(id) ->
      delete_comment(model: model, db: server_context.db, id:)
    DeleteArticle -> delete_article(model: model, db: server_context.db)
  }
}

fn load_article_page(
  db db: sqlight.Connection,
  article_slug article_slug: String,
  maybe_user_id maybe_user_id: Option(Int),
) -> Result(#(ServerModel, ToClient), ServerError) {
  use row <- result.try(query_one(
    query_result: articles_sql.get_by_slug(db: db, slug: article_slug),
    message: "Article not found",
  ))
  use tag_rows <- result.try(sql_result_to_app_error(
    query_result: tags_sql.list_by_article(db: db, article_id: row.id),
    message: "Failed to load tags",
  ))
  use comment_rows <- result.try(sql_result_to_app_error(
    query_result: comments_sql.list_by_article(db: db, article_id: row.id),
    message: "Failed to load comments",
  ))
  use favorite_info <- result.try(get_favorite_info(
    db:,
    article_id: row.id,
    maybe_user_id:,
  ))
  use is_following <- result.try(get_follow_status(
    db:,
    followed_id: row.author_id,
    maybe_user_id:,
  ))

  let #(is_favorited, favorites_count) = favorite_info
  let tags = list.map(tag_rows, fn(row) { row.name })
  let comments =
    list.map(comment_rows, fn(row) {
      Comment(
        id: row.id,
        body: row.body,
        created_at: row.created_at,
        username: row.username,
        image: row.image,
      )
    })
  let article =
    Article(
      id: row.id,
      slug: row.slug,
      title: row.title,
      description: row.description,
      body: row.body,
      created_at: row.created_at,
      tags:,
      author_username: row.username,
      author_image: row.image,
      author_bio: row.bio,
    )

  Ok(#(
    ServerModel(article_id: row.id, author_id: row.author_id),
    ArticleData(
      article:,
      comments:,
      is_favorited:,
      is_following:,
      favorites_count:,
    ),
  ))
}

fn update_favorite(
  model model: ServerModel,
  db db: sqlight.Connection,
) -> #(ServerModel, Effect(ToClient)) {
  case model {
    ServerModelEmpty ->
      article_error(model: model, message: "No article loaded")
    ServerModel(article_id, _author_id) ->
      case toggle_favorite(db: db, article_id:) {
        Ok(#(new_count, is_favorited)) -> #(
          model,
          effect.batch([
            rally_effect.send_to_client(FavoriteUpdated(
              count: new_count,
              is_favorited:,
            )),
            rally_effect.broadcast_to_page(FavoriteCountUpdated(
              count: new_count,
            )),
          ]),
        )
        Error(error) -> article_result_error(model: model, error:)
      }
  }
}

fn toggle_favorite(
  db db: sqlight.Connection,
  article_id article_id: Int,
) -> Result(#(Int, Bool), ServerError) {
  let session_id = rally_effect.get_ws_session()
  use user_id <- result.try(require_user_id(db: db, session_id:))
  use is_favorited <- result.try(is_article_favorited(
    db:,
    user_id:,
    article_id:,
  ))

  case is_favorited {
    True -> {
      use Nil <- result.try(execute_sql(
        query_result: favorites_sql.remove(db:, user_id:, article_id:),
        message: "Failed to unfavorite article",
      ))
      use count <- result.try(get_favorites_count(db: db, article_id:))
      Ok(#(count, False))
    }
    False -> {
      use Nil <- result.try(execute_sql(
        query_result: favorites_sql.add(db:, user_id:, article_id:),
        message: "Failed to favorite article",
      ))
      use count <- result.try(get_favorites_count(db: db, article_id:))
      Ok(#(count, True))
    }
  }
}

fn update_follow(
  model model: ServerModel,
  db db: sqlight.Connection,
  username username: String,
) -> #(ServerModel, Effect(ToClient)) {
  case toggle_follow(db: db, username:) {
    Ok(is_following) -> #(
      model,
      rally_effect.send_to_client(FollowUpdated(is_following:)),
    )
    Error(error) -> article_result_error(model: model, error:)
  }
}

fn toggle_follow(
  db db: sqlight.Connection,
  username username: String,
) -> Result(Bool, ServerError) {
  let session_id = rally_effect.get_ws_session()
  use user_id <- result.try(require_user_id(db: db, session_id:))
  use row <- result.try(query_one(
    query_result: users_sql.get_id_by_username(db: db, username:),
    message: "User not found",
  ))
  let followed_id = row.id
  use is_following <- result.try(is_user_following(
    db:,
    follower_id: user_id,
    followed_id:,
  ))

  case is_following {
    True -> {
      use Nil <- result.try(execute_sql(
        query_result: follows_sql.remove(
          db:,
          follower_id: user_id,
          followed_id:,
        ),
        message: "Failed to unfollow user",
      ))
      Ok(False)
    }
    False -> {
      use Nil <- result.try(execute_sql(
        query_result: follows_sql.add(db:, follower_id: user_id, followed_id:),
        message: "Failed to follow user",
      ))
      Ok(True)
    }
  }
}

fn submit_comment(
  model model: ServerModel,
  db db: sqlight.Connection,
  body body: String,
) -> #(ServerModel, Effect(ToClient)) {
  case model {
    ServerModelEmpty ->
      article_error(model: model, message: "No article loaded")
    ServerModel(article_id, _author_id) -> {
      case string.is_empty(string.trim(body)) {
        True -> article_error(model: model, message: "Comment can't be blank")
        False ->
          case create_comment(db: db, article_id:, body:) {
            Ok(comment) -> #(
              model,
              rally_effect.broadcast_to_page(CommentAdded(comment)),
            )
            Error(error) -> article_result_error(model: model, error:)
          }
      }
    }
  }
}

fn create_comment(
  db db: sqlight.Connection,
  article_id article_id: Int,
  body body: String,
) -> Result(Comment, ServerError) {
  let session_id = rally_effect.get_ws_session()
  use user_id <- result.try(require_user_id(db: db, session_id:))
  let now = datetime.now_unix()
  use row <- result.try(query_one(
    query_result: comments_sql.create(
      db: db,
      body:,
      article_id:,
      author_id: user_id,
      now:,
    ),
    message: "Failed to post comment",
  ))
  use user_row <- result.try(query_one(
    query_result: users_sql.get_info(db: db, user_id:),
    message: "Failed to load comment author",
  ))

  Ok(Comment(
    id: row.id,
    body:,
    created_at: now,
    username: user_row.username,
    image: user_row.image,
  ))
}

fn delete_comment(
  model model: ServerModel,
  db db: sqlight.Connection,
  id id: Int,
) -> #(ServerModel, Effect(ToClient)) {
  let session_id = rally_effect.get_ws_session()
  case require_user_id(db: db, session_id:) {
    Ok(user_id) ->
      case
        comments_sql.delete_own(db: db, id:, author_id: user_id)
        |> sql_result_to_app_error(message: "Failed to delete comment")
      {
        Ok([_]) -> #(model, rally_effect.broadcast_to_page(CommentRemoved(id:)))
        Ok([_, _, ..]) -> #(
          model,
          rally_effect.broadcast_to_page(CommentRemoved(id:)),
        )
        Ok([]) -> #(model, effect.none())
        Error(error) -> article_result_error(model: model, error:)
      }
    Error(error) -> article_result_error(model: model, error:)
  }
}

fn delete_article(
  model model: ServerModel,
  db db: sqlight.Connection,
) -> #(ServerModel, Effect(ToClient)) {
  case model {
    ServerModelEmpty ->
      article_error(model: model, message: "No article loaded")
    ServerModel(article_id, author_id) ->
      case delete_article_if_author(db: db, article_id:, author_id:) {
        Ok(Nil) -> #(
          ServerModelEmpty,
          rally_effect.send_to_client(ArticleDeleted),
        )
        Error(error) -> article_result_error(model: model, error:)
      }
  }
}

fn delete_article_if_author(
  db db: sqlight.Connection,
  article_id article_id: Int,
  author_id author_id: Int,
) -> Result(Nil, ServerError) {
  let session_id = rally_effect.get_ws_session()
  use user_id <- result.try(require_user_id(db: db, session_id:))
  case user_id == author_id {
    True ->
      execute_sql(
        query_result: articles_sql.delete(db: db, article_id:),
        message: "Failed to delete article",
      )
    False -> Error(ServerError("You can only delete your own articles"))
  }
}

fn article_error(
  model model: ServerModel,
  message message: String,
) -> #(ServerModel, Effect(ToClient)) {
  #(model, rally_effect.send_to_client(ArticleError(message)))
}

fn article_result_error(
  model model: ServerModel,
  error error: ServerError,
) -> #(ServerModel, Effect(ToClient)) {
  article_error(model: model, message: error_message(error:))
}

fn require_user_id(
  db db: sqlight.Connection,
  session_id session_id: String,
) -> Result(Int, ServerError) {
  case get_current_user_id(db: db, session_id:) {
    Ok(Some(user_id)) -> Ok(user_id)
    Ok(None) -> Error(ServerError("You must be logged in"))
    Error(error) -> Error(error)
  }
}

fn get_current_user_id(
  db db: sqlight.Connection,
  session_id session_id: String,
) -> Result(Option(Int), ServerError) {
  let now = datetime.now_unix()
  case auth_sql.find_user_by_session(db:, session_id: session_id, now:) {
    Ok([row]) -> {
      use _rows <- result.try(sql_result_to_app_error(
        query_result: auth_sql.extend_session(
          db:,
          expires_at: now + datetime.session_ttl_seconds,
          session_id: session_id,
        ),
        message: "Failed to extend session",
      ))
      Ok(Some(row.id))
    }
    Ok(_) -> Ok(None)
    Error(error) -> Error(sql_error(message: "Failed to read session", error:))
  }
}

fn get_favorite_info(
  db db: sqlight.Connection,
  article_id article_id: Int,
  maybe_user_id maybe_user_id: Option(Int),
) -> Result(#(Bool, Int), ServerError) {
  use count <- result.try(get_favorites_count(db: db, article_id:))
  case maybe_user_id {
    Some(user_id) -> {
      use is_favorited <- result.try(is_article_favorited(
        db:,
        user_id:,
        article_id:,
      ))
      Ok(#(is_favorited, count))
    }
    None -> Ok(#(False, count))
  }
}

fn get_favorites_count(
  db db: sqlight.Connection,
  article_id article_id: Int,
) -> Result(Int, ServerError) {
  use row <- result.try(query_one(
    query_result: favorites_sql.count_for_article(db: db, article_id:),
    message: "Failed to load favorite count",
  ))
  Ok(row.count)
}

fn get_follow_status(
  db db: sqlight.Connection,
  followed_id followed_id: Int,
  maybe_user_id maybe_user_id: Option(Int),
) -> Result(Bool, ServerError) {
  case maybe_user_id {
    Some(user_id) -> is_user_following(db:, follower_id: user_id, followed_id:)
    None -> Ok(False)
  }
}

fn is_article_favorited(
  db db: sqlight.Connection,
  user_id user_id: Int,
  article_id article_id: Int,
) -> Result(Bool, ServerError) {
  use row <- result.try(query_one(
    query_result: favorites_sql.is_favorited(db: db, user_id:, article_id:),
    message: "Failed to check favorite status",
  ))
  Ok(row.count > 0)
}

fn is_user_following(
  db db: sqlight.Connection,
  follower_id follower_id: Int,
  followed_id followed_id: Int,
) -> Result(Bool, ServerError) {
  use row <- result.try(query_one(
    query_result: follows_sql.is_following(db: db, follower_id:, followed_id:),
    message: "Failed to check follow status",
  ))
  Ok(row.count > 0)
}

fn query_one(
  query_result query_result: Result(List(a), sqlight.Error),
  message message: String,
) -> Result(a, ServerError) {
  use rows <- result.try(sql_result_to_app_error(query_result:, message:))
  case rows {
    [row] -> Ok(row)
    _ -> Error(ServerError(message))
  }
}

fn execute_sql(
  query_result query_result: Result(List(a), sqlight.Error),
  message message: String,
) -> Result(Nil, ServerError) {
  use _rows <- result.try(sql_result_to_app_error(query_result:, message:))
  Ok(Nil)
}

fn sql_result_to_app_error(
  query_result query_result: Result(a, sqlight.Error),
  message message: String,
) -> Result(a, ServerError) {
  case query_result {
    Ok(value) -> Ok(value)
    Error(error) -> Error(sql_error(message:, error:))
  }
}

fn sql_error(
  message message: String,
  error error: sqlight.Error,
) -> ServerError {
  let sqlight.SqlightError(message: sql_message, ..) = error
  ServerError(message <> ": " <> sql_message)
}

fn error_message(error error: ServerError) -> String {
  let ServerError(message) = error
  message
}
