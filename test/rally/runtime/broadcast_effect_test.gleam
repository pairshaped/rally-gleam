import gleam/list
import gleeunit/should
import rally/runtime/effect
import rally/runtime/internal/effect_runner
import rally/runtime/internal/effect_state
import rally/runtime/topics

@external(erlang, "rally_test_wire_stub", "register")
fn ensure_test_wire_module() -> Nil

pub fn broadcast_to_page_no_crash_test() {
  ensure_test_wire_module()
  topics.start()
  let page = "TestPage"
  effect_state.put_ws_state(Nil, Nil, page)
  topics.join("page:" <> page)
  effect.broadcast_to_page(#("test", 42))
  |> effect_runner.perform
  let frames = effect_state.drain_outgoing_frames()
  list.length(frames) |> should.equal(1)
}

pub fn discarded_push_effect_does_not_queue_frame_test() {
  ensure_test_wire_module()
  topics.start()
  effect_state.put_ws_state(Nil, Nil, "SomePage")
  let _discarded = effect.send_to_client(#("test", 42))
  let frames = effect_state.drain_outgoing_frames()
  list.length(frames) |> should.equal(0)
}

pub fn performed_push_effect_queues_frame_test() {
  ensure_test_wire_module()
  topics.start()
  effect_state.put_ws_state(Nil, Nil, "SomePage")
  effect.send_to_client(#("test", 42))
  |> effect_runner.perform
  let frames = effect_state.drain_outgoing_frames()
  list.length(frames) |> should.equal(1)
}

pub fn broadcast_to_app_no_crash_test() {
  ensure_test_wire_module()
  topics.start()
  effect_state.put_ws_state(Nil, Nil, "SomePage")
  topics.join("app")
  effect.broadcast_to_app(#("test", 42))
  |> effect_runner.perform
  let frames = effect_state.drain_outgoing_frames()
  list.length(frames) |> should.equal(1)
}

pub fn broadcast_to_session_no_crash_test() {
  ensure_test_wire_module()
  topics.start()
  effect_state.put_ws_state(Nil, Nil, "SomePage")
  effect_state.put_ws_session("test-session-123")
  topics.join("session:test-session-123")
  effect.broadcast_to_session(#("test", 42))
  |> effect_runner.perform
  let frames = effect_state.drain_outgoing_frames()
  list.length(frames) |> should.equal(1)
}
