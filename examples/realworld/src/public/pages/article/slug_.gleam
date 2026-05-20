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
  _client_context: ClientContext,
  _slug: String,
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
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
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

pub fn view(client_context: ClientContext, model: Model) -> Element(Msg) {
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
          article,
          model.is_favorited,
          model.is_following,
          model.favorites_count,
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
              article,
              model.is_favorited,
              model.is_following,
              model.favorites_count,
            ),
          ]),
          comment_section(client_context, model),
        ]),
      ])
  }
}

fn article_banner(
  article: Article,
  is_favorited: Bool,
  is_following: Bool,
  favorites_count: Int,
) -> Element(Msg) {
  html.div([attr.class("banner")], [
    html.div([attr.class("container")], [
      html.h1([], [html.text(article.title)]),
      article_meta(article, is_favorited, is_following, favorites_count),
    ]),
  ])
}

fn article_meta(
  article: Article,
  is_favorited: Bool,
  is_following: Bool,
  favorites_count: Int,
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
  client_context: ClientContext,
  model: Model,
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

pub fn server_init(
  server_context: ServerContext,
  article_slug: String,
) -> #(ServerModel, Effect(ToClient)) {
  let session_id = rally_effect.get_ws_session()
  let maybe_user_id = get_user_id(server_context.db, session_id)
  case articles_sql.get_by_slug(db: server_context.db, slug: article_slug) {
    Ok([row]) -> {
      let assert Ok(tag_rows) =
        tags_sql.list_by_article(db: server_context.db, article_id: row.id)
      let tags = list.map(tag_rows, fn(r) { r.name })
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
      let assert Ok(comment_rows) =
        comments_sql.list_by_article(db: server_context.db, article_id: row.id)
      let comments =
        list.map(comment_rows, fn(c) {
          Comment(
            id: c.id,
            body: c.body,
            created_at: c.created_at,
            username: c.username,
            image: c.image,
          )
        })
      let #(is_favorited, favorites_count) =
        get_favorite_info(server_context.db, row.id, maybe_user_id)
      let is_following =
        get_follow_status(server_context.db, row.author_id, maybe_user_id)
      #(
        ServerModel(article_id: row.id, author_id: row.author_id),
        rally_effect.send_to_client(ArticleData(
          article:,
          comments:,
          is_favorited:,
          is_following:,
          favorites_count:,
        )),
      )
    }
    _ -> #(
      ServerModelEmpty,
      rally_effect.send_to_client(ArticleError("Article not found")),
    )
  }
}

pub fn server_update(
  model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    ToggleFavorite -> {
      case model {
        ServerModelEmpty -> #(
          model,
          rally_effect.send_to_client(ArticleError("No article loaded")),
        )
        ServerModel(article_id, _author_id) -> {
          let session_id = rally_effect.get_ws_session()
          case get_user_id(server_context.db, session_id) {
            Ok(user_id) -> {
              let assert Ok([row]) =
                favorites_sql.is_favorited(
                  db: server_context.db,
                  user_id:,
                  article_id:,
                )
              case row.count > 0 {
                True -> {
                  let assert Ok(_) =
                    favorites_sql.remove(
                      db: server_context.db,
                      user_id:,
                      article_id:,
                    )
                  let new_count =
                    get_favorites_count(server_context.db, article_id)
                  #(
                    model,
                    effect.batch([
                      rally_effect.send_to_client(FavoriteUpdated(
                        count: new_count,
                        is_favorited: False,
                      )),
                      rally_effect.broadcast_to_page(FavoriteCountUpdated(
                        count: new_count,
                      )),
                    ]),
                  )
                }
                False -> {
                  let assert Ok(_) =
                    favorites_sql.add(
                      db: server_context.db,
                      user_id:,
                      article_id:,
                    )
                  let new_count =
                    get_favorites_count(server_context.db, article_id)
                  #(
                    model,
                    effect.batch([
                      rally_effect.send_to_client(FavoriteUpdated(
                        count: new_count,
                        is_favorited: True,
                      )),
                      rally_effect.broadcast_to_page(FavoriteCountUpdated(
                        count: new_count,
                      )),
                    ]),
                  )
                }
              }
            }
            Error(_error) -> #(
              model,
              rally_effect.send_to_client(ArticleError("You must be logged in")),
            )
          }
        }
      }
    }
    ToggleFollow(username) -> {
      let session_id = rally_effect.get_ws_session()
      case get_user_id(server_context.db, session_id) {
        Ok(user_id) -> {
          case users_sql.get_id_by_username(db: server_context.db, username:) {
            Ok([row]) -> {
              let followed_id = row.id
              let assert Ok([existing]) =
                follows_sql.is_following(
                  db: server_context.db,
                  follower_id: user_id,
                  followed_id:,
                )
              case existing.count > 0 {
                True -> {
                  let assert Ok(_) =
                    follows_sql.remove(
                      db: server_context.db,
                      follower_id: user_id,
                      followed_id:,
                    )
                  #(
                    model,
                    rally_effect.send_to_client(FollowUpdated(
                      is_following: False,
                    )),
                  )
                }
                False -> {
                  let assert Ok(_) =
                    follows_sql.add(
                      db: server_context.db,
                      follower_id: user_id,
                      followed_id:,
                    )
                  #(
                    model,
                    rally_effect.send_to_client(FollowUpdated(
                      is_following: True,
                    )),
                  )
                }
              }
            }
            _ -> #(
              model,
              rally_effect.send_to_client(ArticleError("User not found")),
            )
          }
        }
        Error(_error) -> #(
          model,
          rally_effect.send_to_client(ArticleError("You must be logged in")),
        )
      }
    }
    SubmitComment(body) -> {
      case model {
        ServerModelEmpty -> #(
          model,
          rally_effect.send_to_client(ArticleError("No article loaded")),
        )
        ServerModel(article_id, _author_id) -> {
          case string.is_empty(string.trim(body)) {
            True -> #(
              model,
              rally_effect.send_to_client(ArticleError("Comment can't be blank")),
            )
            False -> {
              let session_id = rally_effect.get_ws_session()
              case get_user_id(server_context.db, session_id) {
                Ok(user_id) -> {
                  let now = datetime.now_unix()
                  case
                    comments_sql.create(
                      db: server_context.db,
                      body:,
                      article_id:,
                      author_id: user_id,
                      now: now,
                    )
                  {
                    Ok([row]) -> {
                      let assert Ok([user_row]) =
                        users_sql.get_info(db: server_context.db, user_id:)
                      let comment =
                        Comment(
                          id: row.id,
                          body:,
                          created_at: now,
                          username: user_row.username,
                          image: user_row.image,
                        )
                      #(
                        model,
                        rally_effect.broadcast_to_page(CommentAdded(comment)),
                      )
                    }
                    _ -> #(
                      model,
                      rally_effect.send_to_client(ArticleError(
                        "Failed to post comment",
                      )),
                    )
                  }
                }
                Error(_error) -> #(
                  model,
                  rally_effect.send_to_client(ArticleError(
                    "You must be logged in",
                  )),
                )
              }
            }
          }
        }
      }
    }
    DeleteComment(id) -> {
      let session_id = rally_effect.get_ws_session()
      case get_user_id(server_context.db, session_id) {
        Ok(user_id) -> {
          case
            comments_sql.delete_own(
              db: server_context.db,
              id:,
              author_id: user_id,
            )
          {
            Ok([_]) -> #(
              model,
              rally_effect.broadcast_to_page(CommentRemoved(id:)),
            )
            _ -> #(model, effect.none())
          }
        }
        Error(_error) -> #(
          model,
          rally_effect.send_to_client(ArticleError("You must be logged in")),
        )
      }
    }
    DeleteArticle -> {
      case model {
        ServerModelEmpty -> #(
          model,
          rally_effect.send_to_client(ArticleError("No article loaded")),
        )
        ServerModel(article_id, author_id) -> {
          let session_id = rally_effect.get_ws_session()
          case get_user_id(server_context.db, session_id) {
            Ok(user_id) -> {
              case user_id == author_id {
                True -> {
                  let assert Ok(_) =
                    articles_sql.delete(db: server_context.db, article_id:)
                  #(
                    ServerModelEmpty,
                    rally_effect.send_to_client(ArticleDeleted),
                  )
                }
                False -> #(
                  model,
                  rally_effect.send_to_client(ArticleError(
                    "You can only delete your own articles",
                  )),
                )
              }
            }
            Error(_error) -> #(
              model,
              rally_effect.send_to_client(ArticleError("You must be logged in")),
            )
          }
        }
      }
    }
  }
}

fn get_user_id(db: sqlight.Connection, session_id: String) -> Result(Int, Nil) {
  let now = datetime.now_unix()
  case auth_sql.find_user_by_session(db:, session_id: session_id, now:) {
    Ok([row]) -> {
      let _result =
        auth_sql.extend_session(
          db:,
          expires_at: now + datetime.session_ttl_seconds,
          session_id: session_id,
        )
      Ok(row.id)
    }
    _ -> Error(Nil)
  }
}

fn get_favorite_info(
  db: sqlight.Connection,
  article_id: Int,
  maybe_user_id: Result(Int, Nil),
) -> #(Bool, Int) {
  let count = get_favorites_count(db, article_id)
  let is_favorited = case maybe_user_id {
    Ok(user_id) -> {
      let assert Ok([row]) =
        favorites_sql.is_favorited(db:, user_id:, article_id:)
      row.count > 0
    }
    Error(_error) -> False
  }
  #(is_favorited, count)
}

fn get_favorites_count(db: sqlight.Connection, article_id: Int) -> Int {
  let assert Ok([row]) = favorites_sql.count_for_article(db:, article_id:)
  row.count
}

fn get_follow_status(
  db: sqlight.Connection,
  followed_id: Int,
  maybe_user_id: Result(Int, Nil),
) -> Bool {
  case maybe_user_id {
    Ok(user_id) -> {
      let assert Ok([row]) =
        follows_sql.is_following(db:, follower_id: user_id, followed_id:)
      row.count > 0
    }
    Error(_error) -> False
  }
}
