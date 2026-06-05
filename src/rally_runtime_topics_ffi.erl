-module(rally_runtime_topics_ffi).
-export([start/0, join/1, leave/1, members/1, broadcast/2, broadcast_except_self/2, receive_frame/1]).

start() ->
    case pg:start_link(rally_topics) of
        {ok, _Pid} -> nil;
        {error, {already_started, _Pid}} -> nil
    end.

join(Topic) ->
    pg:join(rally_topics, Topic, self()),
    nil.

leave(Topic) ->
    pg:leave(rally_topics, Topic, self()),
    nil.

members(Topic) ->
    pg:get_members(rally_topics, Topic).

broadcast(Topic, Frame) ->
    broadcast_except_self(Topic, Frame).

broadcast_except_self(Topic, Frame) ->
    Members = pg:get_members(rally_topics, Topic),
    Self = self(),
    lists:foreach(fun(Pid) ->
        case Pid of
            Self -> ok;
            _ -> Pid ! {rally_push, Frame}
        end
    end, Members),
    nil.

receive_frame(TimeoutMs) ->
    receive
        {rally_push, Frame} -> {ok, Frame}
    after TimeoutMs ->
        {error, nil}
    end.
