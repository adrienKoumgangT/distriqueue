%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University Of Pise
%%% @doc
%%%
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

-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {
  worker_load = #{},           % WorkerId -> Load
  worker_capacities = #{},     % WorkerId -> Capacity
  queue_stats = #{},           % Queue -> {Length, ProcessingRate}
  routing_strategy = round_robin
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
  % Initialize with empty state
  {ok, #state{}}.

handle_call({assign_worker, Job}, _From, State) ->
  #job{type = Type, priority = Priority} = Job,

  % Select worker based on strategy
  WorkerId = select_worker(Type, Priority, State),

  % Update worker load (temporary increase)
  NewLoad = case maps:get(WorkerId, State#state.worker_load, 0) of
              Load -> State#state.worker_load#{WorkerId => Load + 1}
            end,

  NewState = State#state{worker_load = NewLoad},

  {reply, {ok, WorkerId}, NewState};

handle_call(get_queue_stats, _From, State) ->
  {reply, {ok, State#state.queue_stats}, State}.

handle_cast({route_job, Job}, State) ->
  #job{id = JobId, priority = Priority} = Job,

  % Determine queue based on priority
  Queue = priority_to_queue(Priority),

  % Publish to RabbitMQ
  rabbitmq_client:publish_job(Queue, Job),

  % Update queue stats
  Stats = maps:get(Queue, State#state.queue_stats, {0, 0}),
  {Length, Rate} = Stats,
  NewStats = State#state.queue_stats#{Queue => {Length + 1, Rate}},

  NewState = State#state{queue_stats = NewStats},

  lager:debug("Routed job ~p to queue ~p", [JobId, Queue]),

  {noreply, NewState};

handle_cast({worker_heartbeat, WorkerId, Capacity, CurrentLoad}, State) ->
  % Update worker information
  NewLoad = State#state.worker_load#{WorkerId => CurrentLoad},
  NewCapacities = State#state.worker_capacities#{WorkerId => Capacity},

  NewState = State#state{
    worker_load = NewLoad,
    worker_capacities = NewCapacities
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
    _ ->
      % Simple round-robin (in real implementation, track last used)
      [Worker | _] = Workers,
      Worker
  end.

select_least_loaded(State) ->
  Workers = maps:to_list(State#state.worker_load),
  case Workers of
    [] -> <<"default_worker">>;
    _ ->
      % Find worker with lowest load/capacity ratio
      {BestWorker, _} = lists:minby(
        fun({WorkerId, Load}) ->
          Capacity = maps:get(WorkerId, State#state.worker_capacities, 10),
          Load / Capacity
        end, Workers),
      BestWorker
  end.

select_by_type(Type, State) ->
  % Map job types to specialized workers
  case Type of
    <<"calculate">> -> <<"python_calc_worker">>;
    <<"transform">> -> <<"java_transform_worker">>;
    <<"validate">> -> <<"go_validate_worker">>;
    _ -> select_least_loaded(State)
  end.

priority_to_queue(Priority) when Priority >= 10 -> <<"job.high">>;
priority_to_queue(Priority) when Priority >= 5 -> <<"job.medium">>;
priority_to_queue(_) -> <<"job.low">>.
