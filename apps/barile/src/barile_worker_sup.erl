%%%-------------------------------------------------------------------
%%% @author tkyshm
%%% @copyright (C) 2016, tkyshm
%%% @doc
%%%
%%% @end
%%% Created : 2016-02-28 17:13:16.273278
%%%-------------------------------------------------------------------
-module(barile_worker_sup).

-behaviour(supervisor).

%% API
-export([start_link/0,
		 spawn_child/1
		]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

spawn_child(Task) ->
	supervisor:start_child(?MODULE, [Task]).

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
	supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
	{ok, {{simple_one_for_one, 100, 600}, [worker_spec()]}}.

%%%===================================================================
%%% internal functions
%%%===================================================================
worker_spec() ->
	{'barile_worker', {'barile_worker', start_link, []},
	 permanent, 5000, worker, ['barile_worker']}.
