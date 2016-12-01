%%%-------------------------------------------------------------------
%%% @author tkyshm
%%% @copyright (C) 2016, tkyshm
%%% @doc
%%%
%%% @end
%%% Created : 2016-02-28 17:18:44.282133
%%%-------------------------------------------------------------------
-module(barile_worker).

-behaviour(gen_server).

%% API
-export([start_link/5,
		 deactivate/1,
		 activate/1,
		 get_status/1
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
		  name      = undefined   :: barile:task_name(),
		  detail    = undefined   :: barile:detail(),
		  cronspec  = undefined   :: term(),
		  tasks     = undefined   :: [barile:task()],
		  next_time = undefined   :: term(),
		  status    = inactivated :: inactivated | activated,
		  env_vars  = undefined   :: [term()]
		 }).

%%%===================================================================
%%% API
%%%===================================================================
-spec deactivate(pid()) -> term().
deactivate(Pid) ->
	gen_server:call(Pid, {deactivate}).

-spec activate(pid()) -> term().
activate(Pid) ->
	gen_server:call(Pid, {activate}).

-spec get_status(pid()) -> term().
get_status(Pid) ->
	gen_server:call(Pid, {get_status}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Name, Detail, Schedule, Tasks, Envs) ->
	gen_server:start_link(?MODULE, [Name, Detail, Schedule, Tasks, Envs], []).

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
init([Name, Detail, Schedule, Tasks, Envs]) ->
	CronSpec = cronparser:time_specs(Schedule),
	{ok, #state{ name = Name, detail = Detail, cronspec = CronSpec, tasks = Tasks ,status = inactivated, env_vars = Envs }}.

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
handle_call({activate}, _From, State = #state{ name = Name, status = Status }) when Status =:= inactivated ->
	error_logger:info_msg("~p Activating...", [Name]),
	self() ! trigger_task,
	{reply, ok, State#state{ status = activated }};
handle_call({activate}, _From, State = #state{ name = Name, status = Status }) when Status =:= activated ->
	error_logger:info_msg("Already ~p is active.", [Name]),
	{reply, already_activated, State};
handle_call({deactivate}, _From, State = #state{ name = Name, status = Status }) when Status =:= activated ->
	error_logger:info_msg("~p Deactivating...", [Name]),
	{reply, ok, State#state{ status = inactivated }};
handle_call({deactivate}, _From, State = #state{ name = Name, status = Status }) when Status =:= inactivated ->
	error_logger:info_msg("Already ~p is inactive.", [Name]),
	{reply, already_inactivated, State};
handle_call({inactivate}, _From, State) ->
	{reply, ok, State#state{ status = inactivated }};
handle_call({get_status}, _From, State) ->
	{reply, State#state.status, State};
handle_call(_Request, _From, State) ->
	{reply, ok, State}.

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
handle_info(trigger_task, State = #state{ name = Name, status = Status }) when Status =:= inactivated ->
	error_logger:info_msg("Not Activated Task: ~ts", [Name]),
	{noreply, State};
handle_info(trigger_task, State = #state{ name = Name, cronspec = CronSpec, status = Status, tasks = Tasks }) when Status =:= activated ->
	%% TODO: need notice result to barile server?
	%% TODO: schedule checkes
	error_logger:info_msg("Activated Job: ~ts", [Name]),
	erlang:send_after(next_time(CronSpec), self(), trigger_task),
	execute_tasks(Tasks),
	{noreply, State};
handle_info(_Info, State) ->
	error_logger:info_msg("nothing to do"),
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
-spec execute_tasks(barile:tasks()) -> term().
execute_tasks(Tasks) ->
	execute_tasks(Tasks, <<>>).

-spec execute_tasks(barile:tasks(), binary()) -> term().
execute_tasks([], Result) ->
	Result;
execute_tasks([{_TaskName, Cmd}|Tasks], Result) ->
	case execute_cmd(Cmd) of
		{ok, Output} ->
			error_logger:info_msg("~ts", [Output]),
			execute_tasks(Tasks, <<Result/binary, Output/binary>>);
		{Reason, Output} ->
			error_logger:error_msg("~p: ~ts", [Reason, Output]),
			<<Result/binary, Output/binary>>
	end.

-spec execute_cmd(binary()|string()) -> {ok, binary()} | {exit_error, binary()} | {port_error, binary()}.
execute_cmd(Cmd) ->
	error_logger:info_msg("Starting task command: ~ts", [Cmd]),
	try erlang:open_port({spawn, Cmd}, [exit_status, stderr_to_stdout, binary, stream]) of
		Port ->
			loop(Port,<<>>)
	catch
		_:Reason ->
			Message = case Reason of
						  badarg ->
							  bad_input_arguments;
						  system_limit ->
							  too_many_used_ports;
						  _ ->
							  file:format_error(Reason)
					  end,
			error_logger:info_msg("task command error: ~ts", [Message]),
			start_error
	end.

-spec loop(port(), binary()) -> {ok, binary()} | {exit_error, binary()} | {port_error, binary()}.
loop(Port, Output) ->
	receive
		{Port, {data, Data}} ->
			error_logger:info_msg("Task output: ~ts from ~p", [Data, Port]),
			loop(Port, <<Output/binary, Data/binary>>);
		{Port, {exit_status, 0}} ->
			error_logger:info_msg("Finished successfully from ~p", [Port]),
			{ok, Output};
		{Port, {exit_status, Status}} ->
			error_logger:error_msg("Failed with exit status (~p): ~ts from ~p", [Status, Output, Port]),
			{exit_error, Output};
		{'EXIT', Port, Reason} ->
			error_logger:error_msg("Failed with port exit: reason ~ts from ~p", [file:format_error(Reason), Port]),
			{port_error, Output}
	end.

-spec next_time(term()) -> non_neg_integer().
next_time(CronSpec) ->
	Now = calendar:local_time(),
	Next = cronparser:next(Now, CronSpec),
	1000 * (calendar:datetime_to_gregorian_seconds(Next) - calendar:datetime_to_gregorian_seconds(Now)).
