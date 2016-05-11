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
-export([start_link/4,
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

-compile([{parse_transform, lager_transform}]).

-define(SERVER, ?MODULE).
-define(INTERVAL, 1000). %% 1000 millisecond = 1 second
-define(INIT_AFTER_SEND_TIME, 5000). %% send_after wait sufficient time.

-record(state, {
          name     = undefined   :: barile:task_name(),
          schedule = undefined   :: barile:schedule(),
          detail   = undefined   :: barile:detail(),
          command  = ""          :: term(),
          status   = inactivated :: inactivated | activated 
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
start_link(Name, Command, Schedule, Detail) ->
        gen_server:start_link(?MODULE, [Name, Command, Schedule, Detail], []).

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
init([Name, Command, Schedule, Detail]) ->
    {ok, #state{ name = Name, schedule = Schedule, detail = Detail, status = inactivated, command = Command }}.

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
    lager:info("~p Activating...", [Name]),
    %{{Y, M, D}, {_, _, _}} = calendar:local_time(),
    %{{Y, M, D}, { , , }}
    erlang:send_after(?INIT_AFTER_SEND_TIME, self(), trigger_task), %% after execute wait sufficient time. 
    {reply, ok, State#state{ status = activated }};
handle_call({activate}, _From, State = #state{ name = Name, status = Status }) when Status =:= activated ->
    lager:debug("Already ~p is active.", [Name]),
    {reply, already_activated, State};
handle_call({deactivate}, _From, State = #state{ name = Name, status = Status }) when Status =:= activated ->
    lager:info("~p Deactivating...", [Name]),
    {reply, ok, State#state{ status = inactivated }};
handle_call({deactivate}, _From, State = #state{ name = Name, status = Status }) when Status =:= inactivated ->
    lager:info("Already ~p is inactive.", [Name]),
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
    lager:debug("Not Activated Task: ~ts", [Name]),
    {noreply, State};
handle_info(trigger_task, State = #state{ name = Name, status = Status, command = Cmd }) when Status =:= activated ->
    %% TODO: need notice result to barile server?
    %% TODO: schedule checkes
    lager:debug("Activated Task: ~ts", [Name]),
    case execute_cmd(Cmd) of
        {ok, Output} ->
            lager:debug("Succeed to execute command( ~p ): ~p", [State#state.command, Output]);
        {Reason, Output} ->
            lager:error("Failed to execute command( ~p ) reason:~p\toutput:~p", [State#state.command, Reason, Output])
    end,
    erlang:send_after(?INTERVAL, self(), trigger_task),
    {noreply, State};
handle_info(_Info, State) ->
    lager:info("nothing to do"),
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
-spec execute_cmd(binary()|string()) -> {ok, binary()} | {exit_error, binary()} | {port_error, binary()}. 
execute_cmd(Cmd) ->
    lager:debug("Starting task command: ~ts", [Cmd]),
    try erlang:open_port({spawn, Cmd}, [exit_status, stderr_to_stdout, binary, stream]) of
        Port ->
            loop(Port,<<>>)
    catch
        _:Reason ->
            case Reason of
                badarg ->
                    Message = bad_input_arguments;
                system_limit ->
                    Message = too_many_used_ports;
                _ ->
                    Message = file:format_error(Reason)
            end,
            lager:error("task command error: ~ts", [Message]),
            start_error
    end.

-spec loop(port(), binary()) -> {ok, binary()} | {exit_error, binary()} | {port_error, binary()}.
loop(Port, Output) ->
    receive
        {Port, {data, Data}} ->
            lager:debug("Task output: ~ts from ~p", [Data, Port]),
            loop(Port, <<Output/binary, Data/binary>>);
        {Port, {exit_status, 0}} ->
            lager:debug("Finished successfully from ~p", [Port]),
            {ok, Output};
        {Port, {exit_status, Status}} ->
            lager:error("Failed with exit status (~p): ~ts from ~p", [Status, Output, Port]),
            {exit_error, Output};
        {'EXIT', Port, Reason} ->
            lager:error("Failed with port exit: reason ~ts from ~p", [file:format_error(Reason), Port]),
            {port_error, Output}
    end.
