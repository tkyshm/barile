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
         add_task/4,
         activate_task/1,
         deactivate_task/1,
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

-compile([{parse_transform, lager_transform}]).

-define(SERVER, ?MODULE).

-record(state, {
          nodes = dict:new() :: dict:dict(node(), node_status()),
          tasks = dict:new() :: dict:dict(task_name(), {pid(), command(), schedule(), detail()})
         }).

-type task_name() :: binary().
%% TODO: specifies the proprietary schedule time format.
-type schedule() :: term().
-type detail() :: binary().
-type command() :: term().
-type task() :: {task_name(), {command(), schedule(), detail()}}.
-type node_status() :: joined | lost | joinning | leaving.

%%%===================================================================
%%% API
%%%===================================================================
%%% @doc
%%% Adds some user's task based on schedule
%%%
%%% @spec add_task(task_name()) -> term()
%%% @end
-spec add_task(task_name(), term(), schedule(), detail()) -> term().
add_task(_Task, "", _Schedule, _Detail) -> 
    lager:debug("Command is empty"),
    invalid_command;
add_task(Task, Command, Schedule, Detail) -> 
    gen_server:call(?SERVER, {add, Task, Command, Schedule, Detail}).

%%% @doc
%%% Activates task
%%%
%%% @spec activate_task(task_name()) -> term()
%%% @end
-spec activate_task(task_name()) -> term().
activate_task(TaskName) -> 
    gen_server:call(?SERVER, {activate, TaskName}).


%%% @doc
%%% Activates task
%%%
%%% @spec activate_task(task_name()) -> term()
%%% @end
-spec deactivate_task(task_name()) -> term().
deactivate_task(TaskName) -> 
    gen_server:call(?SERVER, {deactivate, TaskName}).

%%% @doc
%%% Cancels the task
%%%
%%% @spec cancel_task(task_name()) -> term().
%%% @end
-spec cancel_task(task_name()) -> term().
cancel_task(Task) -> 
    gen_server:call(?SERVER, {cancel, Task}).

%%% @doc
%%% Shows the registered schedule of the task.
%%%
%%% @spec show_schedule(task_name()) -> term().
%%% @end
-spec show_schedule(binary()) -> term().
show_schedule(Task) -> 
    case gen_server:call(?SERVER, {show, Task}) of
        {_TaskName, not_found} ->
            not_found_task;
        %Task = {_TaskName, {_Schedule, _Detail}} ->
        {_TaskName, Bin } ->
            %% TODO: delete theses prints in future. This output is for debug on erlang shell.
            io:format("~ts", [Bin]),
            Bin
    end.

%%% @doc
%%% Shows schedules of all tasks.
%%%
%%% @spec show_schedules() -> term().
%%% @end
-spec show_schedules() -> term().
show_schedules() -> 
    Bins = gen_server:call(?SERVER, {show, all}),
    %% TODO: delete theses prints in future. This output is for debug on erlang shell.
    io:format("[task_name]\t[schedule]\t[description]\n"),
    io:format("~ts",[Bins]),
    Bins.

%%% @doc
%%% Lists up members of distributed nodes.
%%%
%%% @spec members() -> term().
%%% @end
-spec members() -> [term()].
members() -> 
    gen_server:call(?SERVER, {members}).

%%% @doc
%%% Joins a node as barile members.
%%%
%%% @spec members() -> term().
%%% @end
-spec join_node(atom()) -> term().
join_node(Node) -> 
    gen_server:call(?SERVER, {join, Node}).

%%% @doc
%%% Leaves a node from barile members.
%%%
%%% @spec members() -> term().
%%% @end
-spec leave_node(atom()) -> term().
leave_node(Node) -> 
    gen_server:call(?SERVER, {leave, Node}).

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
    {ok, #state{ nodes = dict:store(node(), join, dict:new()) }}.

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
handle_call({add, TaskName, Command, Schedule, Detail}, _From, State = #state{ tasks = Tasks }) ->
    case supervisor:start_child('barile_worker_sup', [TaskName, Command, Schedule, Detail]) of
        {ok, Pid} ->
            %% TODO: receive a message from task worker
            NewTasks = dict:store(TaskName, {Pid, Command, Schedule, Detail}, Tasks),
            lager:info("adds a task: {~p, ~p, ~p, ~p, ~p}", [TaskName, Pid, Command, Schedule, Detail]),
            {reply, ok, State#state{ tasks = NewTasks }};
        {error, Reason} ->
            {stop, Reason, State} 
    end;
handle_call({cancel, TaskName}, _From, State) ->
    %% TODO: receive a message from task worker
    NewTasks = dict:erase(TaskName, State#state.tasks),
    {reply, ok, State#state{ tasks = NewTasks }};
handle_call({show, all}, _From, State) ->
    {reply, format_tasks(dict:to_list(State#state.tasks)), State};
handle_call({show, TaskName}, _From, State) ->
    case dict:find(TaskName, State#state.tasks) of
        error -> 
            {reply, {TaskName, not_found}, State};
        {ok, Task} ->
            {reply, {TaskName, format_task({TaskName, Task})}, State}
    end;
handle_call({members}, _From, State) ->
    {reply, dict:to_list(State#state.nodes), State};
handle_call({join, Node}, _From, State = #state{ nodes = Nodes }) ->
    NewNodes = dict:store(Node, joinning, Nodes),
    % TODO: health checks, if 'Node' is healthy, node status changes 
    %       alive.
    {reply, ok, State#state{ nodes = NewNodes }};
handle_call({leave, Node}, _From, State = #state{ nodes = Nodes }) ->
    case dict:find(Node, Nodes) of 
        error ->
           {reply, {Node, not_found_node}, State};
        _ ->
           % TODO: health checks, if 'Node' is healthy, node status changes 
           %       alive.
           NewNodes = dict:store(Node, leaving, Nodes),
           {reply, ok, State#state{ nodes = NewNodes }}
    end;
handle_call({activate, TaskName}, _From, State = #state{ tasks = Tasks }) ->
    {Pid, _Cmd, _Schedule, _Detail} = dict:fetch(TaskName, Tasks),
    Reply = barile_worker:activate(Pid),
    {reply, Reply, State};
handle_call({deactivate, TaskName}, _From, State = #state{ tasks = Tasks }) ->
    {Pid, _Cmd, _Schedule, _Detail} = dict:fetch(TaskName, Tasks),
    Reply = barile_worker:deactivate(Pid),
    {reply, Reply, State};
handle_call(Request, _From, State) ->
    {reply, {Request, bad_request}, State}.


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
-spec format_tasks([task()]) -> binary().
format_tasks(Tasks) ->
    lists:foldl(fun(X, Acc) -> Line = format_task(X),
                               << Acc/binary, Line/binary >>
                end, <<>>, Tasks). 

-spec format_task(task()) -> binary().
format_task({TaskName, {_Pid, _Cmd, Schedule, Detail}}) ->
    <<TaskName/binary, "\t\t", Schedule/binary, "\t\t", Detail/binary, "\n">>.
