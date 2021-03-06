% Copyright (c) 2012 Benjamin Halsted <bhalsted@gmail.com>
% 
% Permission is hereby granted, free of charge, to any person obtaining a
% copy of this software and associated documentation files (the"Software"),
% to deal in the Software without restriction, including without limitation
% the rights to use, copy, modify, merge, publish, distribute, sublicense,
% and/or sell copies of the Software, and to permit persons to whom the
% Software is furnished to do so, subject to the following conditions:
% 
% The above copyright notice and this permission notice shall be included
% in all copies or substantial portions of the Software.
% 
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
% OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
% THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
% OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
% ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
% OTHER DEALINGS IN THE SOFTWARE.

-module(nlua).

%% API.
-export([load/2]).
-export([send/2]).
-export([load_core/2]).
-export([send_core/2]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-on_load(init/0).

-type lua_ref() :: any().
-export_type([lua_ref/0]).

-define(nif_stub, nif_stub_error(?LINE)).
nif_stub_error(Line) ->
    erlang:nif_error({nif_not_loaded,module,?MODULE,line,Line}).

-spec init() -> ok | {error, {atom(), string()}}.
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

-spec load(binary(), pid()) -> lua_ref().
load(Script, OwnerPid) ->
    load_core(Script, OwnerPid).

-spec send(lua_ref(), [{type | socket | port | event | data | pid | callback_id | reply, any()}]) -> ok | {error, string()}.
send(Lua, Message) ->
    send_core(Lua, Message).

-spec load_core(binary(), pid()) -> lua_ref().
load_core(_Script, _OwnerPid) ->
    ?nif_stub.

-spec send_core(lua_ref(), [{type | socket | port | event | data | pid | callback_id | reply, any()}]) -> ok | {error, string()}.
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
    {ok, Ref} = ?MODULE:load(Script, self()),
    ?assertEqual(ok, ?MODULE:send(Ref, ok)).

bounce_message(Ref, Message) ->
    ?MODULE:send(Ref, { {data, Message}, {pid, self()} }),
    receive 
        Response -> 
            Response
    end.

translation_test_() ->
    {ok, Script} = file:read_file("../test_scripts/incoming_message.lua"),
    {ok, Ref} = ?MODULE:load(Script, self()),
    MakeRefValue = erlang:make_ref(), % this may not work if the erlang environment is cleared
    [
        ?_assertEqual(bounce_message(Ref, ok), <<"ok">>),
        ?_assertEqual(bounce_message(Ref, <<"mkay">>), <<"mkay">>),
        ?_assertEqual(bounce_message(Ref, []), []),
        ?_assertEqual(bounce_message(Ref, 2), 2),
        ?_assertEqual(bounce_message(Ref, -2), -2),
        ?_assertEqual(bounce_message(Ref, -0.2), -0.2),
        ?_assertEqual(bounce_message(Ref, 0.2), 0.2),
        ?_assertEqual(bounce_message(Ref, fun(A) -> A end), <<"sending a function reference is not supported">>),
        ?_assertEqual(bounce_message(Ref, MakeRefValue), MakeRefValue),
        ?_assertEqual(bounce_message(Ref, Ref), Ref),
        ?_assertEqual(bounce_message(Ref, [ok]), [<<"ok">>]),
        ?_assertEqual(bounce_message(Ref, true), true),
        ?_assertEqual(bounce_message(Ref, false), false),
        ?_assertEqual(bounce_message(Ref, nil), nil),
        ?_assertEqual(bounce_message(Ref, [{1, <<"ok">>}]), [<<"ok">>]),
        ?_assertEqual(bounce_message(Ref, [{3, 3}, {2, 2}, one, four, five]), [<<"one">>, 2, 3, <<"four">>, <<"five">>]),
        ?_assertEqual(bounce_message(Ref, {{3, 3}, {2, 2}, one, four, five}), [<<"one">>, 2, 3, <<"four">>, <<"five">>]),
        ?_assertEqual(bounce_message(Ref, [first, {1, <<"ok">>}]), [<<"ok">>,<<"first">>]),
        ?_assertEqual(bounce_message(Ref, {}), []),
        ?_assertEqual(bounce_message(Ref, [{ok, ok}]), [{<<"ok">>,<<"ok">>}]),
        % instead of clobbering KvP with matching K, append them as a list, not awesome, but doesn't lose data
        ?_assertEqual(lists:keysort(1, bounce_message(Ref, [{ok, ok}, {ok, notok}])), [{1,[<<"ok">>,<<"notok">>]},{<<"ok">>,<<"ok">>}]),
        ?_assertEqual(lists:keysort(1, bounce_message(Ref, [{one, ok}, {two, ok}])), [{<<"one">>,<<"ok">>},{<<"two">>,<<"ok">>}]),
        % strings are lists and get treated as such
        ?_assertEqual(bounce_message(Ref, "test"), [116, 101, 115, 116])
    ]
    .

performance_messages(Ref) ->
    PidTuple = {pid, self()},
    [ ?MODULE:send(Ref, { {data, X}, PidTuple }) || X <- lists:seq(1, 10000) ],
    [ receive Y -> Z = erlang:trunc(Y), ?assertEqual(X, Z) end || X <- lists:seq(1, 10000) ].
performance_test() ->
    {ok, Script} = file:read_file("../test_scripts/performance.lua"),
    {ok, Ref} = ?MODULE:load(Script, self()),
    ?debugTime("performance_test", timer:tc(fun performance_messages/1, [Ref])),
    % have to keep a referenco to Ref otherwise it will be
    % garbage collected half way through processing
    io_lib:format("~p processed~n", [Ref]).

owner_pid_test() ->
    MyPid = self(),
    {ok, Script} = file:read_file("../test_scripts/owner_pid.lua"),
    {ok, Ref} = ?MODULE:load(Script, MyPid),
    ?MODULE:send(Ref, ok),
    receive
        Data -> ?assertEqual(MyPid, Data)
    end.


-endif.
