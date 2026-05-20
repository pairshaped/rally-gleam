import gleam/erlang/process
import gleam/list
import rally/runtime/topics

pub fn start_is_idempotent_test() {
  topics.start()
  topics.start()
}

pub fn join_and_members_test() {
  topics.start()
  let topic = "test:join_members"
  topics.join(topic)
  let members = topics.members(topic)
  let assert True = list.length(members) >= 1
  // Clean up
  topics.leave(topic)
}

pub fn leave_removes_member_test() {
  topics.start()
  let topic = "test:leave"
  topics.join(topic)
  topics.leave(topic)
  let members = topics.members(topic)
  let assert True = list.is_empty(members)
}

pub fn broadcast_delivers_to_other_member_test() {
  topics.start()
  let topic = "test:broadcast"
  let frame = <<"hello from broadcaster":utf8>>

  // Subject for the child to signal it has joined
  let joined_subject = process.new_subject()
  // Subject for the child to send the received frame back
  let result_subject = process.new_subject()

  let _pid =
    process.spawn(fn() {
      topics.join(topic)
      // Signal that we've joined
      process.send(joined_subject, Nil)
      case topics.receive_frame(2000) {
        Ok(received) -> process.send(result_subject, received)
        Error(_) -> process.send(result_subject, <<>>)
      }
    })

  // Wait for the child to join
  let assert Ok(Nil) = process.receive(joined_subject, 1000)

  // Broadcast from this process (sender is excluded from delivery)
  topics.join(topic)
  topics.broadcast(topic, frame)

  // The child should receive the frame
  let assert Ok(received) = process.receive(result_subject, 2000)
  let assert True = received == frame

  // Clean up
  topics.leave(topic)
}
