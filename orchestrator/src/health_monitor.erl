%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(health_monitor).
-author("adrien koumgang tegantchouang").
-behaviour(gen_server).

%% API
-export([start_link/0,
  get_system_health/0,
  get_node_health/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {
  node_health = #{},
  last_check,
  check_interval = 30000 % 30 seconds
}).

%%% PUBLIC API %%%
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

get_system_health() ->
  gen_server:call(?MODULE, get_system_health).

get_node_health(Node) ->
  gen_server:call(?MODULE, {get_node_health, Node}).

%%% GEN_SERVER CALLBACKS %%%
init([]) ->
  % Schedule first health check
  erlang:send_after(1000, self(), check_health),
  {ok, #state{}}.

handle_call(get_system_health, _From, State) ->
  Health = State#state.node_health,
  {reply, {ok, Health}, State};

handle_call({get_node_health, Node}, _From, State) ->
  Health = maps:get(Node, State#state.node_health, #{status => unknown}),
  {reply, {ok, Health}, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(check_health, State) ->
  % Check local node health
  LocalHealth = check_local_health(),

  % Check remote nodes
  Nodes = nodes(),
  RemoteHealth = lists:map(
    fun(Node) ->
      {Node, check_remote_health(Node)}
    end, Nodes),

  AllHealth = maps:from_list([{node(), LocalHealth} | RemoteHealth]),

  % Schedule next check
  erlang:send_after(State#state.check_interval, self(), check_health),

  {noreply, State#state{node_health = AllHealth}}.

%%% INTERNAL FUNCTIONS %%%
check_local_health() ->
  #{
    status => healthy,
    memory => erlang:memory(total),
    process_count => erlang:system_info(process_count),
    queue_length => get_queue_length(),
    raft_role => get_raft_role(),
    timestamp => erlang:system_time(millisecond)
  }.

check_remote_health(Node) ->
  case rpc:call(Node, health_monitor, get_system_health, []) of
    {ok, Health} ->
      maps:get(node(), Health, #{status => unknown});
    _ ->
      #{status => unreachable}
  end.

get_queue_length() ->
  try
    {ok, High} = rabbitmq_client:get_queue_info(<<"job.high">>),
    {ok, Medium} = rabbitmq_client:get_queue_info(<<"job.medium">>),
    {ok, Low} = rabbitmq_client:get_queue_info(<<"job.low">>),
    maps:get(count, High, 0) +
      maps:get(count, Medium, 0) +
      maps:get(count, Low, 0)
  catch
    _:_ -> 0
  end.

get_raft_role() ->
  case raft_fsm:get_state() of
    {follower, _, _} -> follower;
    {candidate, _} -> candidate;
    {leader, _} -> leader
  end.
