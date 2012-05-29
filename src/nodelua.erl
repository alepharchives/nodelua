-module(nodelua).

-export([run/1, send/2, reply/2, load/3]).
-export([run_core/1, send_core/2]).

-ifdef(TEST).
-export([callback_test_process/1]).
-include_lib("eunit/include/eunit.hrl").
-endif.

-on_load(init/0).

-define(nif_stub, nif_stub_error(?LINE)).
nif_stub_error(Line) ->
    erlang:nif_error({nif_not_loaded,module,?MODULE,line,Line}).

init() ->
  PrivDir = case code:priv_dir(?MODULE) of
                {error, bad_name} ->
                    EbinDir = filename:dirname(code:which(?MODULE)),
                    AppPath = filename:dirname(EbinDir),
                    filename:join(AppPath, "priv");
                Path ->
                    Path
            end,
    NumProcessors = erlang:system_info(logical_processors),
    erlang:load_nif(filename:join(PrivDir, ?MODULE), NumProcessors).

run(Script) ->
    run_core(Script).

send(Lua, Message) ->
    send_core(Lua, [{pid, self()}, {type, mail}, {data, Message}]).

load(Lua, Path, Module) ->
    send_core(Lua, [{pid, self()}, {type, load}, {module, Module}, {path, Path}]).

reply(LuaCallback, Response) ->
    {1.0, Lua} = lists:nth(1, LuaCallback),
    {2.0, CallbackId} = lists:nth(2, LuaCallback),
    send_core(Lua, [{pid, self()}, {callback_id, CallbackId}, {type, reply}, {reply, Response}]).

run_core(_Script) ->
    ?nif_stub.

send_core(_Ref, _Message) ->
    ?nif_stub.


%% ===================================================================
%% EUnit tests
%% ===================================================================
-ifdef(TEST).

crash1_test() ->
    [ basic_test() || _ <- lists:seq(1, 100) ].

basic_test() ->
    {ok, Script} = file:read_file("../test_scripts/basic_test.lua"),
    {ok, Ref} = run(Script),
    ?assertEqual(ok, send(Ref, ok)).

bounce_message(Ref, Message) ->
    send(Ref, Message),
    receive 
        Response -> 
            Response
    end.

translation_test_() ->
    {ok, Script} = file:read_file("../test_scripts/incoming_message.lua"),
    {ok, Ref} = run(Script),
    MakeRefValue = erlang:make_ref(), % this may not work if the erlang environment is cleared
    [
        ?_assert(bounce_message(Ref, ok) =:= <<"ok">>),
        ?_assert(bounce_message(Ref, <<"mkay">>) =:= <<"mkay">>),
        ?_assert(bounce_message(Ref, []) =:= []),
        ?_assert(bounce_message(Ref, 2) =:= 2.0),
        ?_assert(bounce_message(Ref, -2) =:= -2.0),
        ?_assert(bounce_message(Ref, -0.2) =:= -0.2),
        ?_assert(bounce_message(Ref, 0.2) =:= 0.2),
        ?_assert(bounce_message(Ref, fun(A) -> A end) =:= <<"sending a function reference is not supported">>),
        ?_assert(bounce_message(Ref, MakeRefValue) =:= MakeRefValue),
        ?_assert(bounce_message(Ref, Ref) =:= Ref),
        ?_assert(bounce_message(Ref, [ok]) =:= [{1.0, <<"ok">>}]),
        ?_assert(bounce_message(Ref, true) =:= true),
        ?_assert(bounce_message(Ref, false) =:= false),
        ?_assert(bounce_message(Ref, nil) =:= nil),
        ?_assert(bounce_message(Ref, [{1, <<"ok">>}]) =:= [{1.0, <<"ok">>}]),
        ?_assert(bounce_message(Ref, [{3, 3}, {2, 2}, one, four, five]) =:= [{1.0,<<"one">>}, {2.0,2.0}, {3.0,3.0}, {4.0,<<"four">>}, {5.0,<<"five">>}]),
        ?_assert(bounce_message(Ref, {{3, 3}, {2, 2}, one, four, five}) =:= [{1.0,<<"one">>}, {2.0,2.0}, {3.0,3.0}, {4.0,<<"four">>}, {5.0,<<"five">>}]),
        ?_assert(bounce_message(Ref, [first, {1, <<"ok">>}]) =:= [{1.0,<<"ok">>},{2.0,<<"first">>}]),
        ?_assert(bounce_message(Ref, {}) =:= []),
        ?_assert(bounce_message(Ref, [{ok, ok}]) =:= [{<<"ok">>,<<"ok">>}]),
        % instead of clobbering KvP with matching K, append them as a list, not awesome, but doesn't lose data
        ?_assert(bounce_message(Ref, [{ok, ok}, {ok, notok}]) =:= [{<<"ok">>,<<"ok">>}, {1.0,[{1.0,<<"ok">>},{2.0,<<"notok">>}]}]),
        ?_assert(bounce_message(Ref, [{one, ok}, {two, ok}]) =:= [{<<"one">>,<<"ok">>},{<<"two">>,<<"ok">>}]),
        % strings are lists and get treated as such
        ?_assert(bounce_message(Ref, "test") =:= [{1.0,116.0}, {2.0,101.0}, {3.0,115.0}, {4.0,116.0}])
    ]
    .

performance_messages(Ref) ->
    [ send(Ref, X) || X <- lists:seq(1, 100) ],
    [ receive Y -> Z = erlang:trunc(Y), ?assertEqual(X, Z) end || X <- lists:seq(1, 100) ].
performance_test() ->
    {ok, Script} = file:read_file("../test_scripts/performance.lua"),
    {ok, Ref} = run(Script),
    ?debugTime("performance_test", timer:tc(fun performance_messages/1, [Ref])),
    % have to keep a referenco to Ref otherwise it will be
    % garbage collected half way through processing
    io_lib:format("~p processed~n", [Ref]).

callback_test_process(Pid) ->
    receive
        die -> ok;
        Message -> 
            {_, Sender} = lists:keyfind(<<"sender">>, 1, Message),
            reply(Sender, [{pid, Pid}]),
            callback_test_process(Pid)
    end.

callback_test() ->
    {ok, Script} = file:read_file("../scripts/main.lua"),
    {ok, Ref} = run(Script),
    ?assertEqual(ok, load(Ref, [<<"../scripts/libs">>,<<"../test_scripts">>,<<"../test_scripts/callback_test">>], <<"callback_test">>)),
    EchoPid = spawn(nodelua, callback_test_process, [self()]),
    ?assertEqual(ok, send(Ref, [{echo, EchoPid}])),
    receive
        <<"async-test">> -> EchoPid ! die, ok
    end.

-endif.
