%%%-------------------------------------------------------------------
%%% @author tkyshm
%%% @copyright (C) 2016, tkyshm
%%% @doc
%%% barile is a middleware to schedules and execute any tasks.
%%% barile's goal is a alternative for 'cron' more easy to scale out
%%% and to establish high availavility batch systems.
%%%
%%% @end
%%% Created : 2016-02-28 16:38:21.414009
%%%-------------------------------------------------------------------
-module(barile).

-behaviour(gen_server).

%% API
-export([start_link/0,
         add_task/3,
         cancel_task/1,
         show_schedule/1,
         show_schedules/0,
         members/0,
         join_node/1,
         leave_node/1
        ]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
          nodes = [{node(), alive}] :: [{node(), term()}]
         }).

%% TODO: specifies the proprietary schedule time format.
-type schedule() :: term().
-type detail() :: binary().

%%%===================================================================
%%% API
%%%===================================================================
%%% @doc
%%% Adds some user's task based on schedule
%%%
%%% @spec add_task(binary()) -> term()
%%% @end
-spec add_task(binary(), schedule(), detail()) -> term().
add_task(Task, Schedule, Detail) -> gen_server:call(?SERVER, {add, Task, Schedule, Detail}).

%%% @doc
%%% Cancels the task
%%%
%%% @spec cancel_task(binary()) -> term().
%%% @end
-spec cancel_task(binary()) -> term().
cancel_task(Task) -> gen_server:call(?SERVER, {cancel, Task}).

%%% @doc
%%% Shows the registered schedule of the task.
%%%
%%% @spec show_schedule(binary()) -> term().
%%% @end
-spec show_schedule(binary()) -> term().
show_schedule(Task) -> gen_server:call(?SERVER, {show, Task}).

%%% @doc
%%% Shows schedules of all tasks.
%%%
%%% @spec show_schedules() -> term().
%%% @end
-spec show_schedules() -> term().
show_schedules() -> gen_server:call(?SERVER, {show, all}).

%%% @doc
%%% Lists up members of distributed nodes.
%%%
%%% @spec members() -> term().
%%% @end
-spec members() -> [term()].
members() -> gen_server:call(?SERVER, {members}).

%%% @doc
%%% Joins a node as barile members.
%%%
%%% @spec members() -> term().
%%% @end
-spec join_node(node()) -> term().
join_node(Node) -> gen_server:cast(?SERVER, {join, Node}).

%%% @doc
%%% Leaves a node from barile members.
%%%
%%% @spec members() -> term().
%%% @end
-spec leave_node(node()) -> term().
leave_node(Node) -> gen_server:cast(?SERVER, {leave, Node}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({add, _Task, _Schedule, _Detail}, _From, State) ->
    Reply = ok,
    {reply, Reply, State};
handle_call({cancel, _Task}, _From, State) ->
    Reply = ok,
    {reply, Reply, State};
handle_call({show, all}, _From, State) ->
    Reply = ok,
    {reply, Reply, State};
handle_call({show, _Task}, _From, State) ->
    Reply = ok,
    {reply, Reply, State};
handle_call({members}, _From, State) ->
    Reply = ok,
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({leave, Node}, State) ->
    NewNodes = [{Node, leaving}|State#state.nodes],
    % TODO: health checks, if 'Node' is healthy, node status changes 
    %       alive.
    {noreply, NewNodes};
handle_cast({join, Node}, State) ->
    NewNodes = [{Node, joinning}|State#state.nodes],
    % TODO: health checks, if 'Node' is healthy, node status changes 
    %       alive.
    {noreply, NewNodes};
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
