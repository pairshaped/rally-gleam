%% Rally runtime FFI: WebSocket process state management.
%%
%% These functions manage per-connection state in the process dictionary
%% of the WebSocket handler process. The effect module reads this state
%% to push frames during server-side dispatch.

-module(rally_runtime_ffi).
-export([put_ws_state/3, get_ws_conn/0, get_ws_page/0,
         push_outgoing_frame/1, drain_outgoing_frames/0,
         put_ws_session/1, get_ws_session/0, decode_rally_push/1, decode_rally_push_json/1,
         store_system_conn/1, get_system_conn/0, encode_push_payload/2, encode_push_frame/2,
         put_ws_identity/1, get_ws_identity/0,
         put_ws_hostname/1, get_ws_hostname/0,
         put_ws_auth_timestamp/1, get_ws_auth_timestamp/0,
         clear_ws_auth_state/0]).

put_ws_state(Conn, Ctx, Page) ->
    put(rally_ws_conn, Conn),
    put(rally_ws_ctx, Ctx),
    put(rally_ws_page, Page),
    nil.

get_ws_conn() ->
    case get(rally_ws_conn) of
        undefined -> {error, nil};
        Val -> {ok, Val}
    end.
get_ws_page() ->
    case get(rally_ws_page) of
        undefined -> <<>>;
        Val -> Val
    end.

push_outgoing_frame(Frame) ->
    case get(rally_outgoing_frames) of
        undefined -> put(rally_outgoing_frames, [Frame]);
        Frames -> put(rally_outgoing_frames, [Frame | Frames])
    end,
    nil.

%% Frames are prepended (O(1)) during dispatch, reversed here to preserve send order.
drain_outgoing_frames() ->
    case get(rally_outgoing_frames) of
        undefined -> [];
        Frames -> put(rally_outgoing_frames, []), lists:reverse(Frames)
    end.

put_ws_session(SessionId) ->
    put(rally_ws_session, SessionId),
    nil.

get_ws_session() ->
    case get(rally_ws_session) of
        undefined -> <<>>;
        Val -> Val
    end.

decode_rally_push(Msg) ->
    case Msg of
        {rally_push, Frame} -> {ok, Frame};
        _ -> {error, nil}
    end.

decode_rally_push_json(Msg) ->
    case Msg of
        {rally_push, Frame} -> {ok, Frame};
        _ -> {error, nil}
    end.

store_system_conn(Conn) ->
    persistent_term:put({rally, system_conn}, Conn),
    nil.

get_system_conn() ->
    case persistent_term:get({rally, system_conn}, undefined) of
        undefined -> {error, nil};
        Conn -> {ok, Conn}
    end.

encode_push_payload(Page, Msg) ->
    Mod = persistent_term:get({libero, wire_module}),
    Mod:encode_push(Page, Msg).

encode_push_frame(Page, Msg) ->
    case persistent_term:get({libero, push_frame_module}, undefined) of
        undefined ->
            %% No push frame facade registered; fall back to ETF via Libero boundary.
            case persistent_term:get({libero, wire_module}, undefined) of
                undefined ->
                    'libero@wire':encode_push(Page, Msg);
                Mod ->
                    Encoded = Mod:encode_push(Page, Msg),
                    'libero@wire':encode_push(Page, Encoded)
            end;
        PushMod ->
            %% Single facade: protocol-specific encode + frame in one call.
            PushMod:encode_push_frame(Page, Msg)
    end.

%% --- WS auth state ---

put_ws_identity(Identity) ->
    put(rally_ws_identity, Identity),
    nil.

get_ws_identity() ->
    case get(rally_ws_identity) of
        undefined -> {error, nil};
        Val -> {ok, Val}
    end.

put_ws_hostname(Hostname) ->
    put(rally_ws_hostname, Hostname),
    nil.

get_ws_hostname() ->
    case get(rally_ws_hostname) of
        undefined -> <<>>;
        Val -> Val
    end.

put_ws_auth_timestamp(Ts) ->
    put(rally_ws_auth_ts, Ts),
    nil.

get_ws_auth_timestamp() ->
    case get(rally_ws_auth_ts) of
        undefined -> 0;
        Val -> Val
    end.

%% Clear identity and timestamp (used in tests and reauth failure).
%% Hostname is preserved: it is connection-scoped, not auth-scoped.
clear_ws_auth_state() ->
    erase(rally_ws_identity),
    put(rally_ws_auth_ts, 0),
    nil.
