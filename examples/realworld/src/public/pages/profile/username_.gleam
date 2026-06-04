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
import rally/runtime/effect as rally_effect
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
  client_context _client_context: ClientContext,
  username _username: String,
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
  client_context _client_context: ClientContext,
  model model: Model,
  msg msg: Msg,
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

pub fn view(
  client_context _client_context: ClientContext,
  model model: Model,
) -> Element(Msg) {
  case model.profile {
    None ->
      html.div([attr.class("profile-page")], [
        html.div([attr.class("container")], [html.text("Loading...")]),
      ])
    Some(profile) ->
      html.div([attr.class("profile-page")], [
        user_banner(profile: profile, is_following: model.is_following),
        html.div([attr.class("container")], [
          html.div([attr.class("row")], [
            html.div([attr.class("col-xs-12 col-md-10 offset-md-1")], [
              articles_toggle(active_tab: model.active_tab),
              ..list.map(model.articles, article_preview)
            ]),
          ]),
        ]),
      ])
  }
}

fn user_banner(
  profile profile: Profile,
  is_following is_following: Bool,
) -> Element(Msg) {
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

fn articles_toggle(active_tab active_tab: ProfileTab) -> Element(Msg) {
  html.div([attr.class("articles-toggle")], [
    html.ul([attr.class("nav nav-pills outline-active")], [
      tab_link(
        label: "My Articles",
        tab: MyArticles,
        is_active: active_tab == MyArticles,
      ),
      tab_link(
        label: "Favorited Articles",
        tab: FavoritedArticles,
        is_active: active_tab == FavoritedArticles,
      ),
    ]),
  ])
}

fn tab_link(
  label label: String,
  tab tab: ProfileTab,
  is_active is_active: Bool,
) -> Element(Msg) {
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

type ProfileError {
  ProfileNotLoggedIn
  ProfileSqlError(message: String)
}

pub fn server_init(
  server_context server_context: ServerContext,
  username username: String,
) -> #(ServerModel, Effect(ToClient)) {
  let session_id = rally_effect.get_ws_session()
  case
    load_profile(
      db: server_context.db,
      username:,
      maybe_user_id: get_user_id(db: server_context.db, session_id:),
    )
  {
    Ok(#(model, message)) -> #(model, rally_effect.send_to_client(message))
    Error(error) -> {
      let _message = profile_error_message(error:)
      #(ServerModelEmpty, effect.none())
    }
  }
}

pub fn server_update(
  model model: ServerModel,
  msg msg: ToServer,
  server_context server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    ToggleFollow -> update_follow(model: model, db: server_context.db)
    SwitchTab(tab_name) ->
      switch_tab(model: model, db: server_context.db, tab_name:)
  }
}

fn load_profile(
  db db: sqlight.Connection,
  username username: String,
  maybe_user_id maybe_user_id: Result(Int, ProfileError),
) -> Result(#(ServerModel, ToClient), ProfileError) {
  use row <- result.try(query_one(
    query_result: users_sql.get_by_username(db: db, username:),
    message: "Profile not found",
  ))
  use articles <- result.try(fetch_user_articles(db: db, user_id: row.id))
  use is_following <- result.try(get_follow_status(
    db:,
    followed_id: row.id,
    maybe_user_id:,
  ))

  let profile = Profile(username: row.username, bio: row.bio, image: row.image)
  Ok(#(
    ServerModel(profile_user_id: row.id),
    ProfileData(profile:, articles:, is_following:),
  ))
}

fn update_follow(
  model model: ServerModel,
  db db: sqlight.Connection,
) -> #(ServerModel, Effect(ToClient)) {
  case model {
    ServerModelEmpty -> #(model, effect.none())
    ServerModel(profile_user_id) ->
      case toggle_follow(db: db, profile_user_id:) {
        Ok(Some(is_following)) -> #(
          model,
          rally_effect.send_to_client(FollowUpdated(is_following)),
        )
        Ok(None) -> #(model, effect.none())
        Error(error) -> {
          let _message = profile_error_message(error:)
          #(model, effect.none())
        }
      }
  }
}

fn switch_tab(
  model model: ServerModel,
  db db: sqlight.Connection,
  tab_name tab_name: String,
) -> #(ServerModel, Effect(ToClient)) {
  case model {
    ServerModelEmpty -> #(model, effect.none())
    ServerModel(profile_user_id) ->
      case fetch_profile_articles(db: db, profile_user_id:, tab_name:) {
        Ok(articles) -> #(
          model,
          rally_effect.send_to_client(ProfileArticles(articles)),
        )
        Error(error) -> {
          let _message = profile_error_message(error:)
          #(model, effect.none())
        }
      }
  }
}

fn toggle_follow(
  db db: sqlight.Connection,
  profile_user_id profile_user_id: Int,
) -> Result(Option(Bool), ProfileError) {
  let session_id = rally_effect.get_ws_session()
  use user_id <- result.try(get_user_id(db: db, session_id:))
  case user_id == profile_user_id {
    True -> Ok(None)
    False -> {
      use is_following <- result.try(is_following(
        db:,
        follower_id: user_id,
        followed_id: profile_user_id,
      ))
      case is_following {
        True -> {
          use Nil <- result.try(execute_sql(
            query_result: follows_sql.remove(
              db:,
              follower_id: user_id,
              followed_id: profile_user_id,
            ),
            message: "Failed to unfollow user",
          ))
          Ok(Some(False))
        }
        False -> {
          use Nil <- result.try(execute_sql(
            query_result: follows_sql.add(
              db:,
              follower_id: user_id,
              followed_id: profile_user_id,
            ),
            message: "Failed to follow user",
          ))
          Ok(Some(True))
        }
      }
    }
  }
}

fn get_user_id(
  db db: sqlight.Connection,
  session_id session_id: String,
) -> Result(Int, ProfileError) {
  let now = datetime.now_unix()
  case auth_sql.find_user_by_session(db:, session_id: session_id, now:) {
    Ok([row]) -> {
      use _rows <- result.try(sql_result_to_profile_error(
        query_result: auth_sql.extend_session(
          db:,
          expires_at: now + datetime.session_ttl_seconds,
          session_id: session_id,
        ),
        message: "Failed to extend session",
      ))
      Ok(row.id)
    }
    Ok(_) -> Error(ProfileNotLoggedIn)
    Error(error) ->
      Error(profile_sql_error(message: "Failed to read session", error:))
  }
}

fn get_follow_status(
  db db: sqlight.Connection,
  followed_id followed_id: Int,
  maybe_user_id maybe_user_id: Result(Int, ProfileError),
) -> Result(Bool, ProfileError) {
  case maybe_user_id {
    Ok(user_id) -> is_following(db:, follower_id: user_id, followed_id:)
    Error(ProfileNotLoggedIn) -> Ok(False)
    Error(ProfileSqlError(_) as error) -> Error(error)
  }
}

fn fav_count_to_int(fav_count: Option(String)) -> Int {
  fav_count
  |> option.unwrap("0")
  |> int.parse
  |> result.unwrap(0)
}

fn fetch_user_articles(
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> Result(List(ArticlePreview), ProfileError) {
  use rows <- result.try(sql_result_to_profile_error(
    query_result: articles_sql.list_by_author(db:, author_id: user_id),
    message: "Failed to load user articles",
  ))
  list.map(rows, author_row_to_preview)
  |> Ok
}

fn fetch_favorited_articles(
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> Result(List(ArticlePreview), ProfileError) {
  use rows <- result.try(sql_result_to_profile_error(
    query_result: articles_sql.list_favorited_by_user(db:, user_id:),
    message: "Failed to load favorited articles",
  ))
  list.map(rows, favorited_row_to_preview)
  |> Ok
}

fn fetch_profile_articles(
  db db: sqlight.Connection,
  profile_user_id profile_user_id: Int,
  tab_name tab_name: String,
) -> Result(List(ArticlePreview), ProfileError) {
  case tab_name {
    "favorited" -> fetch_favorited_articles(db: db, user_id: profile_user_id)
    _ -> fetch_user_articles(db: db, user_id: profile_user_id)
  }
}

fn is_following(
  db db: sqlight.Connection,
  follower_id follower_id: Int,
  followed_id followed_id: Int,
) -> Result(Bool, ProfileError) {
  use row <- result.try(query_one(
    query_result: follows_sql.is_following(db:, follower_id:, followed_id:),
    message: "Failed to check follow status",
  ))
  Ok(row.count > 0)
}

fn author_row_to_preview(
  row row: articles_sql.ListByAuthorRow,
) -> ArticlePreview {
  ArticlePreview(
    slug: row.slug,
    title: row.title,
    description: row.description,
    created_at: row.created_at,
    author_username: row.username,
    author_image: row.image,
    favorites_count: fav_count_to_int(row.fav_count),
  )
}

fn favorited_row_to_preview(
  row row: articles_sql.ListFavoritedByUserRow,
) -> ArticlePreview {
  ArticlePreview(
    slug: row.slug,
    title: row.title,
    description: row.description,
    created_at: row.created_at,
    author_username: row.username,
    author_image: row.image,
    favorites_count: fav_count_to_int(row.fav_count),
  )
}

fn query_one(
  query_result query_result: Result(List(a), sqlight.Error),
  message message: String,
) -> Result(a, ProfileError) {
  use rows <- result.try(sql_result_to_profile_error(query_result:, message:))
  case rows {
    [row] -> Ok(row)
    _ -> Error(ProfileSqlError(message))
  }
}

fn execute_sql(
  query_result query_result: Result(List(a), sqlight.Error),
  message message: String,
) -> Result(Nil, ProfileError) {
  use _rows <- result.try(sql_result_to_profile_error(query_result:, message:))
  Ok(Nil)
}

fn sql_result_to_profile_error(
  query_result query_result: Result(a, sqlight.Error),
  message message: String,
) -> Result(a, ProfileError) {
  case query_result {
    Ok(value) -> Ok(value)
    Error(error) -> Error(profile_sql_error(message:, error:))
  }
}

fn profile_sql_error(
  message message: String,
  error error: sqlight.Error,
) -> ProfileError {
  let sqlight.SqlightError(message: sql_message, ..) = error
  ProfileSqlError(message <> ": " <> sql_message)
}

fn profile_error_message(error error: ProfileError) -> String {
  case error {
    ProfileNotLoggedIn -> "Not logged in"
    ProfileSqlError(message:) -> message
  }
}
