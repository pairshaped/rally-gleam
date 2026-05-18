import generated/sql/auth_sql
import gleam/option.{Some}
import helpers/datetime
import public/client_context.{type ClientContext, ClientContext, User}
import sqlight

pub type ServerContext {
  ServerContext(db: sqlight.Connection)
}

pub fn from_session(
  server_context server_context: ServerContext,
  session_id session_id: String,
) -> ClientContext {
  case
    auth_sql.find_user_by_session(
      db: server_context.db,
      session_id: session_id,
      now: datetime.now_unix(),
    )
  {
    Ok([user]) ->
      ClientContext(
        current_user: Some(User(username: user.username, image: user.image)),
      )
    _ -> client_context.init().0
  }
}
