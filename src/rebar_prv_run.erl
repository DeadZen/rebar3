%%% @doc Run scripts commands.
%%% based on a plugin at https://github.com/tsloughter/rebar_alias 
-module(rebar_prv_run).
-author("Pedram Nimreezi <deadzen@deadzen.com>").

-export([init/1,
         do/1]).

-include("rebar.hrl").
-include_lib("providers/include/providers.hrl").
-define(PROVIDER, run).

%% ===================================================================
%% Public API
%% ===================================================================
-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Scripts = rebar_state:get(State, run, []),
    lists:foldl(fun({Run, Cmds}, {ok, StateAcc}) ->
                    case validate_provider(Run, Cmds, State) of
                        true -> init_run(Run, Cmds, StateAcc);
                        false -> 
                            {ok, State}
                    end
                end, {ok, State}, Scripts).
 
init_run(_Run, _Cmds, State) ->
    Provider = providers:create([
            {name, ?PROVIDER},
            {module, ?MODULE},
            {bare, true},
            {deps, []},
            {example, example()},
            {opts, []},
            {short_desc, desc()},
            {desc, desc()}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    CmdArgs = rebar_state:command_args(State),
    Scripts = rebar_state:get(State, run, []),
    case CmdArgs of
        [] -> {ok, State}; %% check for rebar3_run plugin?
        _ ->  run_commands(CmdArgs, Scripts, State)
    end.


run_commands(CmdArgs, Scripts, State) ->
    lists:foreach(fun(Cmd) ->
        case lists:keyfind(list_to_atom(Cmd), 1, Scripts) of
            false ->
              ?WARN("Command: ~p is not in run list: ~p", 
                    [Cmd | [[ Scr || {Scr, _} <- Scripts]] ]);

            {_, [List|_]=RunCmds} when is_list(List) ->
              lists:foreach(fun(Run) ->
                                    {ok, _} = exec(Run)
                            end, RunCmds);
            {_, Run}  ->
              {ok, _} = exec(Run)

        end
    end, CmdArgs),
    {ok, State}.


exec(Run) ->
    ?INFO("Running ~p", [Run]),
    Port = open_port({spawn, Run}, [stream, in, eof, hide, exit_status]),
    {RC, RD} = get_data(Port, []),

    case RC of
        0 -> ok;
        _ -> ?WARN("Non-zero exit code returned: ~p", [RC])
    end,
    io:format("~s", [RD]),
    {ok, {RC, RD}}.	

get_data(Port, Acc) ->
    receive
        {Port, {data, Bytes}} ->
            get_data(Port, [Acc|Bytes]);
        {Port, eof} ->
            Port ! {self(), close},
            ExitCode = receive
                           {Port, {exit_status, Code}} ->
                               Code
                       end,
            {ExitCode, Acc}
    end.


validate_provider(Run, Cmds, _State) ->
    %% check for infinite loops.
    case not validate_loop(Run, Cmds) of
        true -> true;
        false ->
            ?WARN("Run configuration error, '~p' contains itself "
                  "and would never terminate. Refusing to run commands.",
                  [Run]),
            false
    end.


validate_loop(Run, [List|_]=Cmds) when is_list(List) ->
    Any = lists:foldl(fun(Cmd, Acc) ->
        Tokens = string:tokens(Cmd, " "),
        [ lists:member(atom_to_list(Run), Tokens) | Acc ]
    end, [], Cmds),
    lists:member(true, Any);
validate_loop(Run, Cmd) ->
    validate_loop(Run, [Cmd]).


example() ->
    "rebar3 run ...".

desc() ->
    "Run external commands without requiring a Makefile".



