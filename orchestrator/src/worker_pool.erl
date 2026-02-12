%%%-------------------------------------------------------------------
%%% @author adrienkt
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%% Worker Pool Manager - Manages worker registration, health monitoring,
%%% and load balancing for the DistriQueue distributed job scheduler.
%%%
%%% This module maintains the state of all worker nodes, tracks their
%%% health via heartbeats, and provides worker selection for job routing.
%%% @end
%%%-------------------------------------------------------------------
-module(worker_pool).
-author("adrienkt").
-behaviour(gen_server).

%% API
-export([start_link/0,
  register_worker/4,
  unregister_worker/1,
  get_worker/1,
  get_all_workers/0,
  get_healthy_workers/0,
  get_workers_by_type/1,
  update_worker_load/2,
  select_worker/1,
  select_worker/2,
  get_worker_stats/0,
  get_worker_count/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

%% Records
-record(worker, {
  id :: binary(),                    % Worker unique identifier
  type :: binary(),                 % Worker type (python, java, go, etc.)
  status :: active | idle | unresponsive | overloaded | draining,
  capacity :: integer(),           % Maximum concurrent jobs
  current_load :: integer(),       % Current number of running jobs
  last_heartbeat :: integer(),     % Timestamp of last heartbeat
  registered_at :: integer(),      % Registration timestamp
  total_jobs_processed :: integer(), % Total jobs processed by this worker
  failed_jobs :: integer(),        % Number of failed jobs
  avg_processing_time :: float(),  % Average processing time in ms
  metadata :: map()               % Additional worker metadata
}).

-record(state, {
  workers = #{} :: #{binary() => #worker{}},  % All workers by ID
  by_type = #{} :: #{binary() => [binary()]}, % Workers indexed by type
  by_status = #{} :: #{atom() => [binary()]}, % Workers indexed by status
  unhealthy_workers = #{} :: #{binary() => integer()}, % Workers with failures
  total_workers = 0 :: integer(),
  active_workers = 0 :: integer(),
  last_cleanup :: integer(),
  selection_strategy :: round_robin | least_loaded | random,
  round_robin_counter = 0 :: integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Start the worker pool server
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register a new worker or update existing worker heartbeat
-spec register_worker(binary(), binary(), integer(), integer()) -> ok.
register_worker(WorkerId, WorkerType, Capacity, CurrentLoad) ->
  gen_server:call(?MODULE, {register_worker, WorkerId, WorkerType, Capacity, CurrentLoad}).

%% @doc Unregister a worker (graceful shutdown)
-spec unregister_worker(binary()) -> ok.
unregister_worker(WorkerId) ->
  gen_server:cast(?MODULE, {unregister_worker, WorkerId}).

%% @doc Get worker details by ID
-spec get_worker(binary()) -> {ok, #worker{}} | {error, not_found}.
get_worker(WorkerId) ->
  gen_server:call(?MODULE, {get_worker, WorkerId}).

%% @doc Get all registered workers
-spec get_all_workers() -> {ok, [#worker{}]}.
get_all_workers() ->
  gen_server:call(?MODULE, get_all_workers).

%% @doc Get all healthy (active) workers
-spec get_healthy_workers() -> {ok, [#worker{}]}.
get_healthy_workers() ->
  gen_server:call(?MODULE, get_healthy_workers).

%% @doc Get workers by type
-spec get_workers_by_type(binary()) -> {ok, [#worker{}]}.
get_workers_by_type(WorkerType) ->
  gen_server:call(?MODULE, {get_workers_by_type, WorkerType}).

%% @doc Update worker load (jobs count)
-spec update_worker_load(binary(), integer()) -> ok.
update_worker_load(WorkerId, Load) ->
  gen_server:cast(?MODULE, {update_load, WorkerId, Load}).

%% @doc Select a worker for job assignment
-spec select_worker(binary()) -> {ok, binary()} | {error, no_worker}.
select_worker(JobType) ->
  gen_server:call(?MODULE, {select_worker, JobType, default}).

%% @doc Select a worker with specific strategy
-spec select_worker(binary(), atom()) -> {ok, binary()} | {error, no_worker}.
select_worker(JobType, Strategy) ->
  gen_server:call(?MODULE, {select_worker, JobType, Strategy}).

%% @doc Get worker pool statistics
-spec get_worker_stats() -> {ok, map()}.
get_worker_stats() ->
  gen_server:call(?MODULE, get_worker_stats).

%% @doc Get total worker count
-spec get_worker_count() -> {ok, integer()}.
get_worker_count() ->
  gen_server:call(?MODULE, get_worker_count).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @doc Initialize the worker pool
-spec init(term()) -> {ok, #state{}}.
init([]) ->
  process_flag(trap_exit, true),
  lager:info("Worker pool manager starting..."),

  % Schedule periodic health checks
  erlang:send_after(30000, self(), check_worker_health),
  erlang:send_after(60000, self(), cleanup_stale_workers),

  % Get configuration
  Strategy = application:get_env(distriqueue, worker_selection_strategy, least_loaded),

  State = #state{
    selection_strategy = Strategy,
    last_cleanup = erlang:system_time(millisecond)
  },

  lager:info("Worker pool manager started with strategy: ~p", [Strategy]),
  {ok, State}.

%% @doc Handle synchronous calls
-spec handle_call(term(), {pid(), term()}, #state{}) -> {reply, term(), #state{}}.

%% Register new worker or update heartbeat
handle_call({register_worker, WorkerId, WorkerType, Capacity, CurrentLoad}, _From, State) ->
  Now = erlang:system_time(millisecond),

  % Check if worker already exists
  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined ->
      % New worker
      Worker = #worker{
        id = WorkerId,
        type = WorkerType,
        status = active,
        capacity = Capacity,
        current_load = CurrentLoad,
        last_heartbeat = Now,
        registered_at = Now,
        total_jobs_processed = 0,
        failed_jobs = 0,
        avg_processing_time = 0.0,
        metadata = #{}
      },

      NewWorkers = State#state.workers#{WorkerId => Worker},

      % Update by_type index
      TypeWorkers = maps:get(WorkerType, State#state.by_type, []),
      NewByType = State#state.by_type#{WorkerType => [WorkerId | TypeWorkers]},

      % Update by_status index
      StatusWorkers = maps:get(active, State#state.by_status, []),
      NewByStatus = State#state.by_status#{active => [WorkerId | StatusWorkers]},

      NewState = State#state{
        workers = NewWorkers,
        by_type = NewByType,
        by_status = NewByStatus,
        total_workers = State#state.total_workers + 1,
        active_workers = State#state.active_workers + 1
      },

      lager:info("New worker registered: ~p (type: ~p, capacity: ~p)",
        [WorkerId, WorkerType, Capacity]),

      {reply, ok, NewState};

    ExistingWorker ->
      % Update existing worker
      UpdatedWorker = ExistingWorker#worker{
        type = WorkerType,
        capacity = Capacity,
        current_load = CurrentLoad,
        last_heartbeat = Now,
        status = active
      },

      NewWorkers = State#state.workers#{WorkerId => UpdatedWorker},

      % Update status if it was previously unhealthy
      NewByStatus = case ExistingWorker#worker.status of
                      active -> State#state.by_status;
                      _ ->
                        % Remove from old status
                        OldStatusWorkers = maps:get(ExistingWorker#worker.status, State#state.by_status, []),
                        StatusWorkers1 = State#state.by_status#{
                          ExistingWorker#worker.status => lists:delete(WorkerId, OldStatusWorkers)
                        },
                        % Add to active
                        ActiveWorkers = maps:get(active, StatusWorkers1, []),
                        StatusWorkers1#{active => [WorkerId | ActiveWorkers]}
                    end,

      % Update active count if coming back from unhealthy
      ActiveWorkersDelta = case ExistingWorker#worker.status of
                             active -> 0;
                             _ -> 1
                           end,

      NewState = State#state{
        workers = NewWorkers,
        by_status = NewByStatus,
        active_workers = State#state.active_workers + ActiveWorkersDelta
      },

      lager:debug("Worker heartbeat received: ~p (load: ~p/~p)",
        [WorkerId, CurrentLoad, Capacity]),

      {reply, ok, NewState}
  end;

%% Get worker by ID
handle_call({get_worker, WorkerId}, _From, State) ->
  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined ->
      {reply, {error, not_found}, State};
    Worker ->
      {reply, {ok, Worker}, State}
  end;

%% Get all workers
handle_call(get_all_workers, _From, State) ->
  Workers = maps:values(State#state.workers),
  {reply, {ok, Workers}, State};

%% Get healthy workers
handle_call(get_healthy_workers, _From, State) ->
  HealthyWorkers = lists:filter(
    fun(Worker) ->
      Worker#worker.status =:= active andalso
        Worker#worker.current_load < Worker#worker.capacity
    end,
    maps:values(State#state.workers)
  ),
  {reply, {ok, HealthyWorkers}, State};

%% Get workers by type
handle_call({get_workers_by_type, WorkerType}, _From, State) ->
  WorkerIds = maps:get(WorkerType, State#state.by_type, []),
  Workers = lists:map(
    fun(Id) -> maps:get(Id, State#state.workers) end,
    WorkerIds
  ),
  {reply, {ok, Workers}, State};

%% Select worker for job assignment
handle_call({select_worker, JobType, Strategy}, _From, State) ->
  % Get eligible workers (active, not overloaded)
  AllWorkers = maps:values(State#state.workers),
  EligibleWorkers = lists:filter(
    fun(Worker) ->
      Worker#worker.status =:= active andalso
        Worker#worker.current_load < Worker#worker.capacity andalso
        (JobType =:= undefined orelse Worker#worker.type =:= JobType)
    end,
    AllWorkers
  ),

  case EligibleWorkers of
    [] ->
      {reply, {error, no_worker}, State};
    _ ->
      SelectedWorker = case Strategy of
                         round_robin -> select_round_robin(EligibleWorkers, State);
                         least_loaded -> select_least_loaded(EligibleWorkers);
                         random -> select_random(EligibleWorkers);
                         _ -> select_least_loaded(EligibleWorkers)
                       end,

      % Update round-robin counter
      NewCounter = case Strategy of
                     round_robin -> (State#state.round_robin_counter + 1) rem length(EligibleWorkers);
                     _ -> State#state.round_robin_counter
                   end,

      {reply, {ok, SelectedWorker#worker.id},
        State#state{round_robin_counter = NewCounter}}
  end;

%% Get worker statistics
handle_call(get_worker_stats, _From, State) ->
  Workers = maps:values(State#state.workers),

  TotalCapacity = lists:sum([W#worker.capacity || W <- Workers]),
  TotalLoad = lists:sum([W#worker.current_load || W <- Workers]),
  TotalProcessed = lists:sum([W#worker.total_jobs_processed || W <- Workers]),
  TotalFailed = lists:sum([W#worker.failed_jobs || W <- Workers]),

  % Calculate average processing time
  WorkersWithTime = [W#worker.avg_processing_time || W <- Workers, W#worker.avg_processing_time > 0],
  AvgProcessingTime = case WorkersWithTime of
                        [] -> 0.0;
                        _ -> lists:sum(WorkersWithTime) / length(WorkersWithTime)
                      end,

  Stats = #{
    total_workers => State#state.total_workers,
    active_workers => State#state.active_workers,
    unhealthy_workers => maps:size(State#state.unhealthy_workers),
    total_capacity => TotalCapacity,
    current_load => TotalLoad,
    utilization => if TotalCapacity > 0 -> TotalLoad * 100 / TotalCapacity; true -> 0 end,
    total_jobs_processed => TotalProcessed,
    total_jobs_failed => TotalFailed,
    success_rate => if TotalProcessed + TotalFailed > 0 ->
      TotalProcessed * 100 / (TotalProcessed + TotalFailed);
                      true -> 100
                    end,
    avg_processing_time_ms => AvgProcessingTime,
    workers_by_type => maps:map(
      fun(_Type, Ids) -> length(Ids) end,
      State#state.by_type
    ),
    workers_by_status => maps:map(
      fun(_Status, Ids) -> length(Ids) end,
      State#state.by_status
    )
  },

  {reply, {ok, Stats}, State};

%% Get worker count
handle_call(get_worker_count, _From, State) ->
  {reply, {ok, State#state.total_workers}, State}.

%% @doc Handle asynchronous casts
-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.

%% Unregister worker
handle_cast({unregister_worker, WorkerId}, State) ->
  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined ->
      {noreply, State};
    Worker ->
      % Remove from workers map
      NewWorkers = maps:remove(WorkerId, State#state.workers),

      % Remove from by_type index
      TypeWorkers = maps:get(Worker#worker.type, State#state.by_type, []),
      NewByType = State#state.by_type#{
        Worker#worker.type => lists:delete(WorkerId, TypeWorkers)
      },

      % Remove from by_status index
      StatusWorkers = maps:get(Worker#worker.status, State#state.by_status, []),
      NewByStatus = State#state.by_status#{
        Worker#worker.status => lists:delete(WorkerId, StatusWorkers)
      },

      % Remove from unhealthy workers if present
      NewUnhealthy = maps:remove(WorkerId, State#state.unhealthy_workers),

      ActiveDelta = case Worker#worker.status of
                      active -> -1;
                      _ -> 0
                    end,

      NewState = State#state{
        workers = NewWorkers,
        by_type = NewByType,
        by_status = NewByStatus,
        unhealthy_workers = NewUnhealthy,
        total_workers = State#state.total_workers - 1,
        active_workers = State#state.active_workers + ActiveDelta
      },

      lager:info("Worker unregistered: ~p", [WorkerId]),
      {noreply, NewState}
  end;

%% Update worker load
handle_cast({update_load, WorkerId, Load}, State) ->
  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined ->
      {noreply, State};
    Worker ->
      UpdatedWorker = Worker#worker{current_load = Load},
      NewWorkers = State#state.workers#{WorkerId => UpdatedWorker},
      {noreply, State#state{workers = NewWorkers}}
  end;

%% Mark worker as unhealthy
handle_cast({mark_unhealthy, WorkerId, Reason}, State) ->
  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined ->
      {noreply, State};
    Worker when Worker#worker.status =:= active ->
      UpdatedWorker = Worker#worker{
        status = unresponsive,
        metadata = Worker#worker.metadata#{
          last_error => Reason,
          marked_unhealthy_at => erlang:system_time(millisecond)
        }
      },

      NewWorkers = State#state.workers#{WorkerId => UpdatedWorker},

      % Update status index
      ActiveWorkers = maps:get(active, State#state.by_status, []),
      UnresponsiveWorkers = maps:get(unresponsive, State#state.by_status, []),

      NewByStatus = State#state.by_status#{
        active => lists:delete(WorkerId, ActiveWorkers),
        unresponsive => [WorkerId | UnresponsiveWorkers]
      },

      % Track unhealthy worker
      NewUnhealthy = State#state.unhealthy_workers#{WorkerId => erlang:system_time(millisecond)},

      lager:warning("Worker marked unhealthy: ~p - ~p", [WorkerId, Reason]),

      {noreply, State#state{
        workers = NewWorkers,
        by_status = NewByStatus,
        unhealthy_workers = NewUnhealthy,
        active_workers = State#state.active_workers - 1
      }};
    _ ->
      {noreply, State}
  end.

%% @doc Handle asynchronous messages
-spec handle_info(term(), #state{}) -> {noreply, #state{}}.

%% Check worker health - periodic heartbeat monitoring
handle_info(check_worker_health, State) ->
  Now = erlang:system_time(millisecond),
  Timeout = application:get_env(distriqueue, worker_heartbeat_timeout, 120000), % 2 minutes

  lists:foreach(
    fun({WorkerId, Worker}) ->
      LastHB = Worker#worker.last_heartbeat,
      if
        Now - LastHB > Timeout andalso Worker#worker.status =:= active ->
          % Worker hasn't sent heartbeat, mark as unresponsive
          gen_server:cast(?MODULE, {mark_unhealthy, WorkerId,
            <<"Heartbeat timeout">>});
        true ->
          ok
      end
    end,
    maps:to_list(State#state.workers)
  ),

  % Schedule next check
  erlang:send_after(30000, self(), check_worker_health),
  {noreply, State};

%% Cleanup stale workers that have been unhealthy for too long
handle_info(cleanup_stale_workers, State) ->
  Now = erlang:system_time(millisecond),
  CleanupThreshold = application:get_env(distriqueue, worker_cleanup_timeout, 3600000), % 1 hour

  % Find workers that have been unhealthy for too long
  StaleWorkers = maps:filter(
    fun(_WorkerId, UnhealthySince) ->
      Now - UnhealthySince > CleanupThreshold
    end,
    State#state.unhealthy_workers
  ),

  % Unregister stale workers
  lists:foreach(
    fun(WorkerId) ->
      lager:info("Removing stale worker: ~p (unhealthy for >1h)", [WorkerId]),
      gen_server:cast(?MODULE, {unregister_worker, WorkerId})
    end,
    maps:keys(StaleWorkers)
  ),

  % Schedule next cleanup
  erlang:send_after(3600000, self(), cleanup_stale_workers), % 1 hour
  {noreply, State};

%% Handle unknown messages
handle_info(Message, State) ->
  lager:debug("Worker pool received unknown info: ~p", [Message]),
  {noreply, State}.

%% @doc Terminate the worker pool
-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, _State) ->
  lager:info("Worker pool manager shutting down"),
  ok.

%% @doc Code change handler
-spec code_change(term(), #state{}, term()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @doc Select worker using round-robin strategy
-spec select_round_robin([#worker{}], #state{}) -> #worker{}.
select_round_robin(Workers, State) ->
  Index = State#state.round_robin_counter rem length(Workers),
  lists:nth(Index + 1, Workers).

%% @doc Select worker with least current load
-spec select_least_loaded([#worker{}]) -> #worker{}.
select_least_loaded(Workers) ->
  lists:foldl(
    fun(Worker, Acc) ->
      case Acc of
        undefined -> Worker;
        _ ->
          % Compare load percentage
          LoadRatio = Worker#worker.current_load / Worker#worker.capacity,
          AccRatio = Acc#worker.current_load / Acc#worker.capacity,
          if
            LoadRatio < AccRatio -> Worker;
            true -> Acc
          end
      end
    end,
    undefined,
    Workers
  ).

%% @doc Select random worker
-spec select_random([#worker{}]) -> #worker{}.
select_random(Workers) ->
  Index = rand:uniform(length(Workers)) - 1,
  lists:nth(Index + 1, Workers).

%%%===================================================================
%%% Unit Tests
%%%===================================================================

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

worker_pool_test_() ->
  {setup,
    fun setup/0,
    fun cleanup/1,
    [
      fun test_register_worker/0,
      fun test_get_worker/0,
      fun test_select_worker/0,
      fun test_worker_health/0
    ]}.

setup() ->
  application:ensure_all_started(distriqueue),
  {ok, _} = worker_pool:start_link(),
  ok.

cleanup(_) ->
  gen_server:stop(worker_pool).

test_register_worker() ->
  ok = worker_pool:register_worker(<<"worker1">>, <<"python">>, 5, 0),
  {ok, Worker} = worker_pool:get_worker(<<"worker1">>),
  ?assertEqual(<<"worker1">>, Worker#worker.id),
  ?assertEqual(<<"python">>, Worker#worker.type),
  ?assertEqual(5, Worker#worker.capacity),
  ?assertEqual(0, Worker#worker.current_load).

test_get_worker() ->
  ok = worker_pool:register_worker(<<"worker2">>, <<"java">>, 10, 2),
  {ok, Worker} = worker_pool:get_worker(<<"worker2">>),
  ?assertEqual(<<"worker2">>, Worker#worker.id),
  ?assertEqual(10, Worker#worker.capacity),
  ?assertEqual(2, Worker#worker.current_load),
  ?assertEqual({error, not_found}, worker_pool:get_worker(<<"nonexistent">>)).

test_select_worker() ->
  ok = worker_pool:register_worker(<<"worker3">>, <<"python">>, 5, 0),
  ok = worker_pool:register_worker(<<"worker4">>, <<"python">>, 5, 3),
  ok = worker_pool:register_worker(<<"worker5">>, <<"java">>, 10, 1),

  {ok, Selected} = worker_pool:select_worker(<<"python">>),
  ?assert(lists:member(Selected, [<<"worker3">>, <<"worker4">>])),

  % Should select least loaded (worker3 with load 0)
  {ok, LeastLoaded} = worker_pool:select_worker(<<"python">>, least_loaded),
  ?assertEqual(<<"worker3">>, LeastLoaded).

test_worker_health() ->
  ok = worker_pool:register_worker(<<"worker6">>, <<"go">>, 5, 0),

  % Simulate health check
  worker_pool:update_worker_load(<<"worker6">>, 2),
  {ok, Worker} = worker_pool:get_worker(<<"worker6">>),
  ?assertEqual(2, Worker#worker.current_load).

-endif.
