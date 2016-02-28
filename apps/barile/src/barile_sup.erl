%%%-------------------------------------------------------------------
%% @doc barile top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module('barile_sup').

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    BarileSpec = {'barile', {'barile', start_link, []},
                  temporary, 5000, worker, ['barile']},
    WorkerSupSpec = {'barile_worker_sup', {'barile_worker_sup', start_link, []},
                     permanent, infinity, supervisor, ['barile_worker_sup']},
    {ok, {{one_for_all, 100, 600}, [BarileSpec, WorkerSupSpec]}}.

%%====================================================================
%% Internal functions
%%====================================================================
