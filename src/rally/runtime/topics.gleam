// Topic pub/sub via OTP pg (process groups). Each WS handler process joins
// topics on connect; broadcasts send frames to all members of a group.
// Erlang-only because pg is a BEAM primitive with no JS equivalent.

@target(erlang)
import gleam/dynamic/decode
@target(erlang)
import gleam/erlang/atom
@target(erlang)
import gleam/erlang/process.{type Selector}
@target(erlang)
import gleam/result

@external(erlang, "rally_runtime_topics_ffi", "start")
pub fn start() -> Nil {
  Nil
}

@external(erlang, "rally_runtime_topics_ffi", "join")
pub fn join(_topic: String) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_topics_ffi", "leave")
pub fn leave(_topic: String) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_topics_ffi", "members")
pub fn members(_topic: String) -> List(a) {
  []
}

@external(erlang, "rally_runtime_topics_ffi", "broadcast")
pub fn broadcast(_topic: String, _frame: a) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_topics_ffi", "broadcast_except_self")
pub fn broadcast_except_self(_topic: String, _frame: a) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_topics_ffi", "receive_frame")
pub fn receive_frame(_timeout_ms: Int) -> Result(a, Nil) {
  Error(Nil)
}

@target(erlang)
pub fn frame_selector() -> Selector(BitArray) {
  process.new_selector()
  |> process.select_record(
    tag: atom.create("rally_push"),
    fields: 1,
    mapping: fn(msg) {
      msg
      |> decode.run(decode.at([1], decode.bit_array))
      |> result.unwrap(<<>>)
    },
  )
}
