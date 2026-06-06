-module(rally_cli_ffi).
-export([find_executable/1, run_executable/2, run_in_dir/3,
         run_interactive_in_dir/3, stop_port_listener/1, unique_id/0]).

find_executable(Name) ->
  case os:find_executable(binary_to_list(Name)) of
    false -> none;
    Path -> {some, list_to_binary(Path)}
  end.

run_executable(Program, Args) ->
  CmdArgs = [binary_to_list(A) || A <- Args],
  Port = open_port({spawn_executable, binary_to_list(Program)},
                   [{args, CmdArgs}, exit_status, stderr_to_stdout]),
  Result = loop_until_exit(Port, []),
  {Status, _Output} = Result,
  Status.

loop_until_exit(Port, Acc) ->
  receive
    {Port, {data, Data}} ->
      loop_until_exit(Port, [Data | Acc]);
    {Port, {exit_status, Status}} ->
      {Status, lists:flatten(lists:reverse(Acc))}
  end.

run_in_dir(Program, Args, Dir) ->
  CmdArgs = [binary_to_list(A) || A <- Args],
  Port = open_port({spawn_executable, binary_to_list(Program)},
                   [{args, CmdArgs}, {cd, binary_to_list(Dir)},
                    exit_status, stderr_to_stdout]),
  {Status, Output} = loop_until_exit(Port, []),
  {Status, list_to_binary(Output)}.

run_interactive_in_dir(Program, Args, Dir) ->
  CmdArgs = [binary_to_list(A) || A <- Args],
  Port = open_port({spawn_executable, binary_to_list(Program)},
                   [{args, CmdArgs}, {cd, binary_to_list(Dir)},
                    exit_status, stderr_to_stdout]),
  loop_interactive_until_exit(Port).

loop_interactive_until_exit(Port) ->
  receive
    {Port, {data, Data}} ->
      io:put_chars(Data),
      loop_interactive_until_exit(Port);
    {Port, {exit_status, Status}} ->
      Status
  end.

stop_port_listener(Port) ->
  PortString = integer_to_list(Port),
  PidOutput = os:cmd(
    "command -v lsof >/dev/null 2>&1 && lsof -ti tcp:" ++ PortString ++ " || true"
  ),
  Pids = [Pid || Pid <- string:tokens(PidOutput, "\n\r "), Pid =/= ""],
  lists:foreach(fun(Pid) ->
    os:cmd("kill " ++ Pid ++ " >/dev/null 2>&1 || true")
  end, Pids),
  case Pids of
    [] -> 0;
    _ ->
      timer:sleep(200),
      RemainingOutput = os:cmd(
        "command -v lsof >/dev/null 2>&1 && lsof -ti tcp:" ++ PortString ++ " || true"
      ),
      Remaining = [
        Pid || Pid <- string:tokens(RemainingOutput, "\n\r "), Pid =/= ""
      ],
      lists:foreach(fun(Pid) ->
        os:cmd("kill -9 " ++ Pid ++ " >/dev/null 2>&1 || true")
      end, Remaining),
      length(Pids)
  end.

unique_id() ->
  erlang:integer_to_binary(erlang:unique_integer()).
