# Server Messaging

Rally pages talk to the server through page-local load/save contracts. The Rally Scoreboard example is the reference: the authored page owns `ServerMsg`, `LoadResult`, `load`, optional `handle_save`, typed topics, and `apply_broadcast` when the page needs live updates.

## Load

Use `load` for server-side data needed before first render or browser navigation.

```gleam
pub type LoadResult {
  PublicHomeLoaded(count: Int)
}

@target(erlang)
pub fn load(db: sqlight.Connection) -> Result(Int, load.LoadError) {
  counter_sql.get(db)
}
```

Rally calls `load` during SSR, encodes the result through Libero, embeds hydration flags in the HTML document, and uses the same typed result during browser navigation.

## Save

Use a page-local `ServerMsg` and `handle_save` for server work triggered by browser updates.

```gleam
pub type ServerMsg {
  PublicHomeIncrement
}

pub type CounterUpdate {
  CounterUpdate(count: Int)
}

pub type SaveError {
  SaveError(message: String)
}

@target(erlang)
pub fn handle_save(
  db: sqlight.Connection,
  message: ServerMsg,
) -> Result(CounterUpdate, SaveError) {
  case message {
    PublicHomeIncrement -> counter_sql.increment(db)
  }
}
```

On the browser target, generated Rally modules expose page-specific functions such as `generated/rally/server.save_public_home`.

```gleam
@target(javascript)
fn save_effect(msg: ServerMsg) -> Effect(Message) {
  server.save_public_home(
    message: msg,
    on_result: Saved,
  )
}
```

Rally derives the wire contract from page-local handlers and passes the
reachable Gleam types to Libero as codec seeds. You do not write a separate API
schema, route, or serializer.

Rally discovers the save result payload from the `Ok` type in `handle_save`'s return
annotation. The payload name is application-owned; it does not need to follow a
framework-specific naming pattern.

## Broadcast

Broadcast-aware pages define typed topics and event payloads in app code, usually in a shared module. Page `broadcast_subscriptions` hooks express interest for the current model or route, and page `apply_broadcast` hooks merge decoded events into the page model. Keep them together in a `// BROADCAST` section.

Rally maps typed topics to compact topic frames, stores active subscriptions per connection, filters broadcasts on the server, and skips sending a broadcast back to the initiating connection.
