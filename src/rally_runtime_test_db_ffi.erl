-module(rally_runtime_test_db_ffi).
-export([clone_db/1, pt_put/2, pt_get/2, connection_usable/1]).

clone_db(Template) ->
    {ok, Dest} = esqlite3:open(":memory:"),
    {ok, Backup} = esqlite3:backup_init(Dest, "main", Template, "main"),
    '$done' = esqlite3:backup_step(Backup, -1),
    ok = esqlite3:backup_finish(Backup),
    {ok, Dest}.

pt_put(Key, Value) ->
    persistent_term:put(Key, Value),
    nil.

pt_get(Key, Default) ->
    try persistent_term:get(Key)
    catch error:badarg -> Default
    end.

connection_usable(Connection) ->
    try esqlite3:q(Connection, <<"SELECT 1">>, []) of
        {error, _} -> false;
        _ -> true
    catch
        _:_ -> false
    end.
