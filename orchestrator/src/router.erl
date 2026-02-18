%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University Of Pise
%%% @doc
%%% Job Router implementation
%%% @end
%%%-------------------------------------------------------------------
-module(router).
-author("adrien koumgang tegantchouang").
-behaviour(gen_server).

%% API
-export([start_link/0,
  route_job/1,
  assign_worker/1,
  get_queue_stats/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include("distriqueue.hrl").

-record(state, {
  worker_load = #{} :: map(),           % WorkerId -> Load
  worker_capacities = #{} :: map(),     % WorkerId -> Capacity
  queue_stats = #{} :: map(),           % Queue -> {Length, ProcessingRate}
  routing_strategy = round_robin :: atom()
}).

%%% PUBLIC API %%%
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

route_job(Job) ->
  gen_server:cast(?MODULE, {route_job, Job}).

assign_worker(Job) ->
  gen_server:call(?MODULE, {assign_worker, Job}).

get_queue_stats() ->
  gen_server:call(?MODULE, get_queue_stats).

%%% GEN_SERVER CALLBACKS %%%
init([]) ->
  {ok, #state{}}.

handle_call({assign_worker, Job}, _From, State) ->
  #job{type = Type, priority = Priority} = Job,

  WorkerId = select_worker(Type, Priority, State),

  %% FIX: Extract the map first, then update it
  CurrentLoadMap = State#state.worker_load,
  NewLoadMap = case maps:get(WorkerId, CurrentLoadMap, 0) of
                 Load -> CurrentLoadMap#{WorkerId => Load + 1}
               end,

  NewState = State#state{worker_load = NewLoadMap},

  {reply, {ok, WorkerId}, NewState};

handle_call(get_queue_stats, _From, State) ->
  {reply, {ok, State#state.queue_stats}, State}.

handle_cast({route_job, Job}, State) ->
  #job{id = JobId, priority = Priority} = Job,

  Queue = priority_to_queue(Priority),

  rabbitmq_client:publish_job(Queue, Job),

  %% FIX: Extract the map first, then update it
  CurrentStatsMap = State#state.queue_stats,
  Stats = maps:get(Queue, CurrentStatsMap, {0, 0}),
  {Length, Rate} = Stats,

  NewStatsMap = CurrentStatsMap#{Queue => {Length + 1, Rate}},
  NewState = State#state{queue_stats = NewStatsMap},

  lager:debug("Routed job ~p to queue ~p", [JobId, Queue]),

  {noreply, NewState};

handle_cast({worker_heartbeat, WorkerId, Capacity, CurrentLoad}, State) ->
  %% FIX: Extract maps first
  CurrentLoadMap = State#state.worker_load,
  CurrentCapMap = State#state.worker_capacities,

  NewLoadMap = CurrentLoadMap#{WorkerId => CurrentLoad},
  NewCapMap = CurrentCapMap#{WorkerId => Capacity},

  NewState = State#state{
    worker_load = NewLoadMap,
    worker_capacities = NewCapMap
  },

  {noreply, NewState}.

handle_info(_Info, State) ->
  {noreply, State}.

%%% INTERNAL FUNCTIONS %%%
select_worker(Type, _Priority, State) ->
  case State#state.routing_strategy of
    round_robin ->
      select_round_robin(State);
    least_loaded ->
      select_least_loaded(State);
    type_based ->
      select_by_type(Type, State)
  end.

select_round_robin(State) ->
  Workers = maps:keys(State#state.worker_load),
  case Workers of
    [] -> <<"default_worker">>;
    [Worker | _] -> Worker
  end.

select_least_loaded(State) ->
  Workers = maps:to_list(State#state.worker_load),
  case Workers of
    [] -> <<"default_worker">>;
    _ ->
      %% Use a manual fold to find the minimum to avoid missing list functions
      {BestWorker, _} = lists:foldl(
        fun({WorkerId, Load}, {AccWorker, AccRatio}) ->
          Capacity = maps:get(WorkerId, State#state.worker_capacities, 10),
          Ratio = Load / Capacity,
          if Ratio < AccRatio -> {WorkerId, Ratio};
            true -> {AccWorker, AccRatio}
          end
        end,
        {<<"default_worker">>, 999999.0},
        Workers),
      BestWorker
  end.

select_by_type(Type, State) ->
  case Type of
    <<"calculate">> -> <<"python_calc_worker">>;
    <<"transform">> -> <<"java_transform_worker">>;
    <<"validate">> -> <<"go_validate_worker">>;
    _ -> select_least_loaded(State)
  end.

priority_to_queue(Priority) when Priority >= 10 -> <<"job.high">>;
priority_to_queue(Priority) when Priority >= 5 -> <<"job.medium">>;
priority_to_queue(_) -> <<"job.low">>.
