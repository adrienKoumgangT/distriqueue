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

-include("distriqueue.hrl").

%% API
-export([start_link/0,
  route_job/1,
  assign_worker/1,
  get_queue_stats/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {
  worker_load = #{} :: map(),           % WorkerId -> Load
  worker_capacities = #{} :: map(),     % WorkerId -> Capacity
  queue_stats = #{} :: map(),           % Queue -> {Length, ProcessingRate}
  routing_strategy = least_loaded :: atom()
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
  {ok, #state{routing_strategy = least_loaded}}.

handle_call({assign_worker, Job}, _From, State) ->
  Type = case is_record(Job, job) of
           true -> Job#job.type;
           false when is_map(Job) -> maps:get(<<"type">>, Job, <<"unknown">>);
           _ -> <<"unknown">>
         end,

  Priority = case is_record(Job, job) of
               true -> Job#job.priority;
               false when is_map(Job) -> maps:get(<<"priority">>, Job, 5);
               _ -> 5
             end,

  WorkerId = select_worker(Type, Priority, State),

  CurrentLoadMap = State#state.worker_load,
  NewLoadMap = case maps:get(WorkerId, CurrentLoadMap, 0) of
                 Load -> CurrentLoadMap#{WorkerId => Load + 1}
               end,

  NewState = State#state{worker_load = NewLoadMap},

  {reply, {ok, WorkerId}, NewState};

handle_call(get_queue_stats, _From, State) ->
  {reply, {ok, State#state.queue_stats}, State}.

handle_cast({route_job, Job}, State) ->
  JobId = case is_record(Job, job) of
            true -> Job#job.id;
            false when is_map(Job) -> maps:get(<<"id">>, Job, <<"unknown">>);
            _ -> <<"unknown">>
          end,

  Priority = case is_record(Job, job) of
               true -> Job#job.priority;
               false when is_map(Job) -> maps:get(<<"priority">>, Job, 5);
               _ -> 5
             end,

  Queue = priority_to_queue(Priority),

  rabbitmq_client:publish_job(Queue, Job),

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
      select_least_loaded_by_type(Type, State);
    type_based ->
      select_by_type(Type, State)
  end.

select_least_loaded_by_type(Type, _State) ->
  %% Get all workers registered for this type from the pool
  case dq_worker_pool:get_workers_by_type(Type) of
    [] ->
      lager:warning("No workers found for type ~p, falling back to default", [Type]),
      <<"default_worker">>;
    Workers ->
      %% Find the worker with the lowest Load/Capacity ratio
      {BestWorkerId, _BestRatio} = lists:foldl(
        fun(W, {AccId, AccRatio}) ->
          %% Calculate load ratio (current_load / capacity)
          %% Ensure we don't divide by zero if capacity is weirdly 0
          Cap = case W#worker.capacity of 0 -> 1; C -> C end,
          Ratio = W#worker.current_load / Cap,

          if Ratio < AccRatio -> {W#worker.id, Ratio};
            true -> {AccId, AccRatio}
          end
        end,
        {<<"none">>, 999999.0},
        Workers),

      case BestWorkerId of
        <<"none">> -> <<"default_worker">>;
        Id -> Id
      end
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
    _ -> select_least_loaded(State)
  end.

priority_to_queue(Priority) when Priority >= 10 -> <<"job.high">>;
priority_to_queue(Priority) when Priority >= 5 -> <<"job.medium">>;
priority_to_queue(_) -> <<"job.low">>.
