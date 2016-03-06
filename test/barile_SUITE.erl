%%%-------------------------------------------------------------------
%%% @author tkyshm
%%% @copyright (C) 2016, tkyshm
%%% @doc
%%%
%%% @end
%%% Created : 2016-03-05 19:24:27.476243
%%%-------------------------------------------------------------------
-module(barile_SUITE).


%% API
-export([all/0,
         suite/0,
         groups/0,
         init_per_suite/1,
         end_per_suite/1,
         group/1,
         init_per_group/2,
         end_per_group/2,
         init_per_testcase/2,
         end_per_testcase/2]).

%% test cases
-export([
         %% TODO: test case names go here
         add_task_test/1,
         load_config/1
        ]).

%-include_lib("proper/include/proper.hrl").
-include_lib("common_test/include/ct.hrl").

%-define(PROPTEST(M,F), true = proper:quickcheck(M:F())).

all() ->
    [
     %% TODO: Group names here e.g. {group, crud}
     {group, add_task}
    ].

suite() ->
    [{ct_hooks,[cth_surefire]}, {timetrap, {seconds, 30}}].

groups() ->
    [
        %% TODO: group definitions here e.g.
        %% {crud, [], [
        %%          t_create_resource,
        %%          t_read_resource,
        %%          t_update_resource,
        %%          t_delete_resource
        %%         ]}
        {add_task, [sequence], [
                                add_task_test,
                                load_config
                               ]}
    ].

%%%===================================================================
%%% Overall setup/teardown
%%%===================================================================
init_per_suite(Config) ->
    application:ensure_all_started(lager),
    application:ensure_all_started(barile),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(barile),
    ok.


%%%===================================================================
%%% Group specific setup/teardown
%%%===================================================================
group(_Groupname) ->
    [].

init_per_group(_Groupname, Config) ->
    Config.

end_per_group(_Groupname, _Config) ->

    ok.

%%%===================================================================
%%% Testcase specific setup/teardown
%%%===================================================================
init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%%===================================================================
%%% Individual Test Cases (from groups() definition)
%%%===================================================================
add_task_test(_Config) ->
    Sch = {[10,11], [20,30], [], 15},
    barile:add_task(<<"task1">>, <<"./test/scripts/test.sh">>, Sch, <<"detail 1">>),
    ct:pal( "~p~n",[ barile:show_schedule(<<"task1">>) ]),
    { _, <<"./test/scripts/test.sh">>, Sch, <<"detail 1">> } = barile:show_schedule(<<"task1">>).

load_config(Config) ->
    {_, DataDir} = lists:keyfind(data_dir, 1, Config),
    barile:file(DataDir ++ "test.toml"),
    %B = <<"task1\t[ 10,11:20,30 all_day period:15min ]\tdetail 1\nmy_task2\t[ 8:27 all_day period:15min ]\tTest schedule 2\nmy_task1\t[ 10,16:27,47 1,2,3,4,5 period:15min ]\tTest schedule 1\n">>,
    _Tasks = barile:show_schedules().
