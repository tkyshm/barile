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
-export([start_link/3,
         inactivate/1,
         activate/1
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
-spec inactivate(pid()) -> term().
inactivate(Pid) -> 
    gen_server:call(Pid, {inactivate}).

-spec activate(pid()) -> term().
activate(Pid) -> 
    gen_server:call(Pid, {activate}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Name, Schedule, Detail) ->
        gen_server:start_link(?MODULE, [Name, Schedule, Detail], []).

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
init([Name, Schedule, Detail]) ->
    erlang:send_after(1000, self(), trigger_task),
    {ok, #state{ name = Name, schedule = Schedule, detail = Detail, status = inactivated }}.

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
handle_call({activate}, _From, State) ->
    {reply, ok, State#state{ status = activated }};
handle_call({inactivate}, _From, State) ->
    {reply, ok, State#state{ status = inactivated }};
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
            lager:debug("Succeed to execute command( ~p ): ~p", [State#state.command, Output]),
            {noreply, State};
        {Reason, Output} ->
            lager:error("Failed to execute command( ~p ): ~p", [State#state.command, Output]),
            {noreply, State}
    end;
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

loop(Port, Output) ->
    receive
        {Port, {data, Data}} ->
            lager:debug("Task output: ~ts from ~p", [Data, Port]),
            loop(Port,<<Output/binary, Data/binary>>);
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
