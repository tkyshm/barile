%%%-------------------------------------------------------------------
%%% @author tkyshm
%%% @copyright (C) 2016, tkyshm
%%% @doc
%%% barile is a middleware to schedules and execute any jobs.
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
		 add_job/1,
		 file/1,
		 activate_job/1,
		 deactivate_job/1,
		 delete_job/1,
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
		  nodes = dict:new() :: dict:dict(node(), node_status()),
		  jobs  = dict:new() :: dict:dict(job_name(), {pid(), job()})
		 }).

-type job()         :: {job_name(), detail(), schedule(), [task()], [env_var()]}.
-type job_name()    :: binary() | term().
-type detail()      :: binary() | term().
-type schedule()    :: binary() | term().
-type task()        :: {task_name(), command()}.
-type env_var()     :: term().
-type task_name()   :: binary().
-type command()     :: term().
-type node_status() :: joined | lost | joinning | leaving.

%%%===================================================================
%%% API
%%%===================================================================

%%% @doc
%%% Adds some user's task based on schedule
%%%
%%% @spec add_task(task_name()) -> term()
%%% @end
-spec add_job(job()) -> term().
add_job(Job) ->
	error_logger:info_msg("Add a job: ~p", [Job]),
	gen_server:call(?SERVER, {add_job, Job}).

%%% @doc
%%% Set job schedules from yaml file
%%%
%%% @spec file(binary()|string()) -> [task()]
%%% @end
-spec file(binary()|string()) -> [task()].
file(Filename) when is_binary(Filename) ->
	file(binary_to_term(Filename));
file(Filename) ->
	[L] = yamerl_constr:file(Filename),
	Job = yaml_to_jobs(L),
	error_logger:info_msg("~p", [Job]),
	add_job(Job).

%%% @doc
%%% Activates job
%%%
%%% @spec activate_task(task_name()) -> term()
%%% @end
-spec activate_job(task_name()) -> term().
activate_job(JobName) ->
	gen_server:call(?SERVER, {activate, JobName}).

%%% @doc
%%% Deactivates job
%%%
%%% @spec activate_task(task_name()) -> term()
%%% @end
-spec deactivate_job(task_name()) -> term().
deactivate_job(JobName) ->
	gen_server:call(?SERVER, {deactivate, JobName}).

%%% @doc
%%% Cancels the task
%%%
%%% @spec cancel_task(task_name()) -> term().
%%% @end
-spec delete_job(task_name()) -> term().
delete_job(JobName) ->
	gen_server:call(?SERVER, {delete_job, JobName}).

%%% @doc
%%% Shows the registered schedule of the task.
%%%
%%% @spec show_schedule(task_name()) -> term().
%%% @end
-spec show_schedule(binary()) -> term().
show_schedule(JobName) ->
	case gen_server:call(?SERVER, {show, JobName}) of
		{_Name, not_found} ->
			not_found_job;
		{JobName, Task} ->
			%% TODO: delete theses prints in future. This output is for debug on erlang shell.
			Task
	end.

%%% @doc
%%% Shows schedules of all jobs.
%%%
%%% @spec show_schedules() -> term().
%%% @end
-spec show_schedules() -> term().
show_schedules() ->
	Tasks = gen_server:call(?SERVER, {show, all}),
	%% TODO: delete theses prints in future. This output is for debug on erlang shell.
	io:format("-----------------------------------------------------------------------------------------------------------------------------------\n"),
	io:format("  Schedules\n"),
	io:format("-----------------------------------------------------------------------------------------------------------------------------------\n"),
	lists:foreach(fun(Row) ->
						  Pid      = proplists:get_value(pid,      Row),
						  JobName  = proplists:get_value(job_name, Row),
						  Status   = proplists:get_value(status,   Row),
						  Schedule = proplists:get_value(schedule, Row),
						  Detail   = proplists:get_value(detail,   Row),
						  io:format("~8p | ~-18ts | ~12p | ~-12ts | ~-24ts~n", [Pid, JobName, Status, Schedule, Detail])
				  end, Tasks).

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
handle_call({add_job, Job = {JobName, _Detail, _Schedule, _Tasks, _Envs }}, _From, State = #state{ jobs = Jobs }) ->
	case dict:find(JobName, Jobs) of
		error ->
			case barile_worker_sup:spawn_child(Job) of
				{ok, Pid} ->
					NewJobs = dict:store(JobName, {Pid, Job}, Jobs),
					error_logger:info_msg("Adds a job ~p, PID: ~P", [Job, Pid]),
					{reply, ok, State#state{jobs = NewJobs}};
				{error, Reason} ->
					{reply, Reason, State}
			end;
		_ ->
			{reply, already_registered_job_name, State}
	end;
handle_call({delete_job, JobName}, _From, State = #state{jobs = Jobs}) ->
	case dict:find(JobName, Jobs) of
		error ->
			{reply, {JobName, not_found}, State};
		{ok, {Pid, _Detail, _Schedule, _Tasks}} ->
			barile_worker:deactivate(Pid),
			NewJobs = dict:erase(JobName, Jobs),
			error_logger:info_msg("Deleted a job ~ts (PID: ~p).", [JobName, Pid]),
			{reply, ok, State#state{ jobs = NewJobs }}
	end;
handle_call({show, all}, _From, State = #state{ jobs = Jobs }) ->
	List = lists:map(fun({JobName, {P, {JobName, Det, Sch, _Tasks, _Envs}}}) ->
							 Status = barile_worker:get_status(P),
							 [
							  {pid, P}
							  , {job_name, JobName}
							  , {status, Status}
							  , {schedule, Sch}
							  , {detail, Det}
							 ]
					 end, dict:to_list(Jobs)),
	{reply, List, State};
handle_call({show, TaskName}, _From, State) ->
	case dict:find(TaskName, State#state.jobs) of
		error ->
			{reply, {TaskName, not_found}, State};
		{ok, Task} ->
			error_logger:info( "~p", [ Task ] ),
			{reply, {TaskName, Task}, State}
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
handle_call({activate, JobName}, _From, State = #state{ jobs = Jobs }) ->
	{Pid, {_JobName, _Detail, _Schedule, _Tasks, _Envs}} = dict:fetch(JobName, Jobs),
	Reply = barile_worker:activate(Pid),
	{reply, Reply, State};
handle_call({deactivate, JobName}, _From, State = #state{ jobs = Jobs }) ->
	{Pid, {_JobName, _Detail, _Schedule, _Tasks, _Envs}} = dict:fetch(JobName, Jobs),
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

-spec yaml_to_jobs([term()]) -> [task()].
yaml_to_jobs(L) ->
	JobName  = proplists:get_value("job_name",L),
	Envs     = proplists:get_value("env",L),
	Detail   = proplists:get_value("description", L),
	Cron     = proplists:get_value("cron", proplists:get_value("schedule", L)),
	Tasks    = proplists:get_value("tasks", L),
	NewTasks = lists:foldl(fun(Line, Acc) ->
								   TaskName = case proplists:lookup("name", Line) of
												  none ->
													  throw(not_found_name_field);
												  {"name", Name} ->
													  Name
											  end,
								   Command = case proplists:lookup("command", Line) of
												 none ->
													 "";
												 {"command", Cmd} ->
													 term_to_binary(Cmd)
											 end,
								   [{TaskName, Command}|Acc]
						   end, [], Tasks),
	{JobName, Detail, Cron, NewTasks, Envs}.
