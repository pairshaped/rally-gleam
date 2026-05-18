import generated/sql/articles_sql
import generated/sql/auth_sql
import generated/sql/follows_sql
import generated/sql/users_sql
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import helpers/datetime
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import public/client_context.{type ClientContext}
import rally_runtime/effect as rally_effect
import server_context.{type ServerContext}
import sqlight

// MODEL

pub type Model {
  Model(
    profile: Option(Profile),
    articles: List(ArticlePreview),
    active_tab: ProfileTab,
    is_following: Bool,
  )
}

pub type Profile {
  Profile(username: String, bio: String, image: String)
}

pub type ArticlePreview {
  ArticlePreview(
    slug: String,
    title: String,
    description: String,
    created_at: Int,
    author_username: String,
    author_image: String,
    favorites_count: Int,
  )
}

pub type ProfileTab {
  MyArticles
  FavoritedArticles
}

pub fn init(
  _client_context: ClientContext,
  _username: String,
) -> #(Model, Effect(Msg)) {
  #(
    Model(
      profile: None,
      articles: [],
      active_tab: MyArticles,
      is_following: False,
    ),
    effect.none(),
  )
}

// UPDATE

pub type Msg {
  ClickedFollow
  ClickedTab(ProfileTab)
  GotServerMsg(ToClient)
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    ClickedFollow -> #(model, rally_effect.send_to_server(ToggleFollow))
    ClickedTab(tab) -> {
      let tab_name = case tab {
        MyArticles -> "my_articles"
        FavoritedArticles -> "favorited"
      }
      #(
        Model(..model, active_tab: tab),
        rally_effect.send_to_server(SwitchTab(tab_name:)),
      )
    }
    GotServerMsg(ProfileData(profile, articles, is_following)) -> #(
      Model(..model, profile: Some(profile), articles:, is_following:),
      effect.none(),
    )
    GotServerMsg(FollowUpdated(is_following)) -> #(
      Model(..model, is_following:),
      effect.none(),
    )
    GotServerMsg(ProfileArticles(articles)) -> #(
      Model(..model, articles:),
      effect.none(),
    )
  }
}

// VIEW

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  case model.profile {
    None ->
      html.div([attr.class("profile-page")], [
        html.div([attr.class("container")], [html.text("Loading...")]),
      ])
    Some(profile) ->
      html.div([attr.class("profile-page")], [
        user_banner(profile, model.is_following),
        html.div([attr.class("container")], [
          html.div([attr.class("row")], [
            html.div([attr.class("col-xs-12 col-md-10 offset-md-1")], [
              articles_toggle(model.active_tab),
              ..list.map(model.articles, article_preview)
            ]),
          ]),
        ]),
      ])
  }
}

fn user_banner(profile: Profile, is_following: Bool) -> Element(Msg) {
  let follow_class = case is_following {
    True -> "btn btn-sm btn-secondary action-btn"
    False -> "btn btn-sm btn-outline-secondary action-btn"
  }
  let follow_text = case is_following {
    True -> "Unfollow " <> profile.username
    False -> "Follow " <> profile.username
  }
  html.div([attr.class("user-info")], [
    html.div([attr.class("container")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-xs-12 col-md-10 offset-md-1")], [
          html.img([attr.class("user-img"), attr.src(profile.image)]),
          html.h4([], [html.text(profile.username)]),
          html.p([], [html.text(profile.bio)]),
          html.button(
            [attr.class(follow_class), event.on_click(ClickedFollow)],
            [
              html.i([attr.class("ion-plus-round")], []),
              html.text(" " <> follow_text),
            ],
          ),
        ]),
      ]),
    ]),
  ])
}

fn articles_toggle(active_tab: ProfileTab) -> Element(Msg) {
  html.div([attr.class("articles-toggle")], [
    html.ul([attr.class("nav nav-pills outline-active")], [
      tab_link("My Articles", MyArticles, active_tab == MyArticles),
      tab_link(
        "Favorited Articles",
        FavoritedArticles,
        active_tab == FavoritedArticles,
      ),
    ]),
  ])
}

fn tab_link(label: String, tab: ProfileTab, is_active: Bool) -> Element(Msg) {
  let active_class = case is_active {
    True -> "nav-link active"
    False -> "nav-link"
  }
  html.li([attr.class("nav-item")], [
    html.a(
      [
        attr.class(active_class),
        attr.href("#"),
        event.on_click(ClickedTab(tab)),
      ],
      [html.text(label)],
    ),
  ])
}

fn article_preview(article: ArticlePreview) -> Element(Msg) {
  html.div([attr.class("article-preview")], [
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
      html.button([attr.class("btn btn-outline-primary btn-sm pull-xs-right")], [
        html.i([attr.class("ion-heart")], []),
        html.text(" " <> int.to_string(article.favorites_count)),
      ]),
    ]),
    html.a(
      [attr.class("preview-link"), attr.href("/article/" <> article.slug)],
      [
        html.h1([], [html.text(article.title)]),
        html.p([], [html.text(article.description)]),
        html.span([], [html.text("Read more...")]),
      ],
    ),
  ])
}

// SERVER

pub type ToServer {
  ToggleFollow
  SwitchTab(tab_name: String)
}

pub type ToClient {
  ProfileData(
    profile: Profile,
    articles: List(ArticlePreview),
    is_following: Bool,
  )
  FollowUpdated(Bool)
  ProfileArticles(List(ArticlePreview))
}

pub type ServerModel {
  ServerModel(profile_user_id: Int)
  ServerModelEmpty
}

pub fn server_init(
  server_context: ServerContext,
  username: String,
) -> #(ServerModel, Effect(ToClient)) {
  let session_id = rally_effect.get_ws_session()
  let maybe_user_id = get_user_id(server_context.db, session_id)
  case users_sql.get_by_username(db: server_context.db, username:) {
    Ok([row]) -> {
      let profile =
        Profile(username: row.username, bio: row.bio, image: row.image)
      let articles = fetch_user_articles(server_context.db, row.id)
      let is_following =
        get_follow_status(server_context.db, row.id, maybe_user_id)
      #(
        ServerModel(profile_user_id: row.id),
        rally_effect.send_to_client(ProfileData(
          profile:,
          articles:,
          is_following:,
        )),
      )
    }
    _ -> #(ServerModelEmpty, effect.none())
  }
}

pub fn server_update(
  model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    ToggleFollow -> {
      case model {
        ServerModelEmpty -> #(model, effect.none())
        ServerModel(profile_user_id) -> {
          let session_id = rally_effect.get_ws_session()
          case get_user_id(server_context.db, session_id) {
            Ok(user_id) if user_id == profile_user_id -> #(model, effect.none())
            Ok(user_id) -> {
              let assert Ok([existing]) =
                follows_sql.is_following(
                  db: server_context.db,
                  follower_id: user_id,
                  followed_id: profile_user_id,
                )
              case existing.count > 0 {
                True -> {
                  let assert Ok(_) =
                    follows_sql.remove(
                      db: server_context.db,
                      follower_id: user_id,
                      followed_id: profile_user_id,
                    )
                  #(model, rally_effect.send_to_client(FollowUpdated(False)))
                }
                False -> {
                  let assert Ok(_) =
                    follows_sql.add(
                      db: server_context.db,
                      follower_id: user_id,
                      followed_id: profile_user_id,
                    )
                  #(model, rally_effect.send_to_client(FollowUpdated(True)))
                }
              }
            }
            Error(_error) -> #(model, effect.none())
          }
        }
      }
    }
    SwitchTab(tab_name) -> {
      case model {
        ServerModelEmpty -> #(model, effect.none())
        ServerModel(profile_user_id) -> {
          let articles = case tab_name {
            "favorited" ->
              fetch_favorited_articles(server_context.db, profile_user_id)
            _ -> fetch_user_articles(server_context.db, profile_user_id)
          }
          #(model, rally_effect.send_to_client(ProfileArticles(articles)))
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

fn fav_count_to_int(fav_count: Option(String)) -> Int {
  fav_count
  |> option.unwrap("0")
  |> int.parse
  |> result.unwrap(0)
}

fn fetch_user_articles(
  db: sqlight.Connection,
  user_id: Int,
) -> List(ArticlePreview) {
  let assert Ok(rows) = articles_sql.list_by_author(db:, author_id: user_id)
  list.map(rows, fn(r) {
    ArticlePreview(
      slug: r.slug,
      title: r.title,
      description: r.description,
      created_at: r.created_at,
      author_username: r.username,
      author_image: r.image,
      favorites_count: fav_count_to_int(r.fav_count),
    )
  })
}

fn fetch_favorited_articles(
  db: sqlight.Connection,
  user_id: Int,
) -> List(ArticlePreview) {
  let assert Ok(rows) = articles_sql.list_favorited_by_user(db:, user_id:)
  list.map(rows, fn(r) {
    ArticlePreview(
      slug: r.slug,
      title: r.title,
      description: r.description,
      created_at: r.created_at,
      author_username: r.username,
      author_image: r.image,
      favorites_count: fav_count_to_int(r.fav_count),
    )
  })
}
