%%%-------------------------------------------------------------------
%%% @author adrienkt
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%% Worker Pool Manager - Manages worker registration, health monitoring,
%%% and load balancing for the DistriQueue distributed job scheduler.
%%%-------------------------------------------------------------------
-module(dq_worker_pool).
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
  id :: binary(),
  type :: binary(),
  status :: active | idle | unresponsive | overloaded | draining,
  capacity :: integer(),
  current_load :: integer(),
  last_heartbeat :: integer(),
  registered_at :: integer(),
  total_jobs_processed :: integer(),
  failed_jobs :: integer(),
  avg_processing_time :: float(),
  metadata :: map()
}).

-record(state, {
  workers = #{} :: #{binary() => #worker{}},
  by_type = #{} :: #{binary() => [binary()]},
  by_status = #{} :: #{atom() => [binary()]},
  unhealthy_workers = #{} :: #{binary() => integer()},
  total_workers = 0 :: integer(),
  active_workers = 0 :: integer(),
  last_cleanup :: integer(),
  selection_strategy :: round_robin | least_loaded | random,
  round_robin_counter = 0 :: integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

register_worker(WorkerId, WorkerType, Capacity, CurrentLoad) ->
  gen_server:call(?MODULE, {register_worker, WorkerId, WorkerType, Capacity, CurrentLoad}).

unregister_worker(WorkerId) ->
  gen_server:cast(?MODULE, {unregister_worker, WorkerId}).

get_worker(WorkerId) ->
  gen_server:call(?MODULE, {get_worker, WorkerId}).

get_all_workers() ->
  gen_server:call(?MODULE, get_all_workers).

get_healthy_workers() ->
  gen_server:call(?MODULE, get_healthy_workers).

get_workers_by_type(WorkerType) ->
  gen_server:call(?MODULE, {get_workers_by_type, WorkerType}).

update_worker_load(WorkerId, Load) ->
  gen_server:cast(?MODULE, {update_load, WorkerId, Load}).

select_worker(JobType) ->
  gen_server:call(?MODULE, {select_worker, JobType, default}).

select_worker(JobType, Strategy) ->
  gen_server:call(?MODULE, {select_worker, JobType, Strategy}).

get_worker_stats() ->
  gen_server:call(?MODULE, get_worker_stats).

get_worker_count() ->
  gen_server:call(?MODULE, get_worker_count).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

init([]) ->
  process_flag(trap_exit, true),
  lager:info("Worker pool manager starting..."),

  erlang:send_after(30000, self(), check_worker_health),
  erlang:send_after(60000, self(), cleanup_stale_workers),

  Strategy = application:get_env(distriqueue, worker_selection_strategy, least_loaded),

  State = #state{
    selection_strategy = Strategy,
    last_cleanup = erlang:system_time(millisecond)
  },
  {ok, State}.

handle_call({register_worker, WorkerId, WorkerType, Capacity, CurrentLoad}, _From, State) ->
  Now = erlang:system_time(millisecond),

  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined ->
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

      CurrentWorkers = State#state.workers,
      NewWorkers = CurrentWorkers#{WorkerId => Worker},

      CurrentByType = State#state.by_type,
      TypeWorkers = maps:get(WorkerType, CurrentByType, []),
      NewByType = CurrentByType#{WorkerType => lists:usort([WorkerId | TypeWorkers])},

      CurrentByStatus = State#state.by_status,
      StatusWorkers = maps:get(active, CurrentByStatus, []),
      NewByStatus = CurrentByStatus#{active => lists:usort([WorkerId | StatusWorkers])},

      NewState = State#state{
        workers = NewWorkers,
        by_type = NewByType,
        by_status = NewByStatus,
        total_workers = State#state.total_workers + 1,
        active_workers = State#state.active_workers + 1
      },
      {reply, ok, NewState};

    ExistingWorker ->
      UpdatedWorker = ExistingWorker#worker{
        type = WorkerType,
        capacity = Capacity,
        current_load = CurrentLoad,
        last_heartbeat = Now,
        status = active
      },

      CurrentWorkers = State#state.workers,
      NewWorkers = CurrentWorkers#{WorkerId => UpdatedWorker},

      CurrentByStatus = State#state.by_status,
      NewByStatus = case ExistingWorker#worker.status of
                      active -> CurrentByStatus;
                      _ ->
                        OldStatusWorkers = maps:get(ExistingWorker#worker.status, CurrentByStatus, []),
                        StatusWorkers1 = CurrentByStatus#{
                          ExistingWorker#worker.status => lists:delete(WorkerId, OldStatusWorkers)
                        },
                        ActiveWorkers = maps:get(active, StatusWorkers1, []),
                        StatusWorkers1#{active => lists:usort([WorkerId | ActiveWorkers])}
                    end,

      ActiveWorkersDelta = case ExistingWorker#worker.status of
                             active -> 0;
                             _ -> 1
                           end,

      NewState = State#state{
        workers = NewWorkers,
        by_status = NewByStatus,
        active_workers = State#state.active_workers + ActiveWorkersDelta
      },
      {reply, ok, NewState}
  end;

handle_call({get_worker, WorkerId}, _From, State) ->
  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined -> {reply, {error, not_found}, State};
    Worker -> {reply, {ok, Worker}, State}
  end;

handle_call(get_all_workers, _From, State) ->
  Workers = maps:values(State#state.workers),
  {reply, {ok, Workers}, State};

handle_call(get_healthy_workers, _From, State) ->
  HealthyWorkers = lists:filter(
    fun(Worker) ->
      Worker#worker.status =:= active andalso
        Worker#worker.current_load < Worker#worker.capacity
    end,
    maps:values(State#state.workers)
  ),
  {reply, {ok, HealthyWorkers}, State};

handle_call({get_workers_by_type, WorkerType}, _From, State) ->
  WorkerIds = maps:get(WorkerType, State#state.by_type, []),
  Workers = lists:filtermap(
    fun(Id) ->
      case maps:find(Id, State#state.workers) of
        {ok, W} -> {true, W};
        error -> false
      end
    end,
    WorkerIds
  ),
  {reply, {ok, Workers}, State};

handle_call({select_worker, JobType, Strategy}, _From, State) ->
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

      NewCounter = case Strategy of
                     round_robin -> (State#state.round_robin_counter + 1) rem length(EligibleWorkers);
                     _ -> State#state.round_robin_counter
                   end,

      {reply, {ok, SelectedWorker#worker.id},
        State#state{round_robin_counter = NewCounter}}
  end;

handle_call(get_worker_stats, _From, State) ->
  Workers = maps:values(State#state.workers),

  TotalCapacity = lists:sum([W#worker.capacity || W <- Workers]),
  TotalLoad = lists:sum([W#worker.current_load || W <- Workers]),
  TotalProcessed = lists:sum([W#worker.total_jobs_processed || W <- Workers]),
  TotalFailed = lists:sum([W#worker.failed_jobs || W <- Workers]),

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
    success_rate => if TotalProcessed + TotalFailed > 0 -> TotalProcessed * 100 / (TotalProcessed + TotalFailed); true -> 100 end,
    avg_processing_time_ms => AvgProcessingTime,
    workers_by_type => maps:map(fun(_Type, Ids) -> length(Ids) end, State#state.by_type),
    workers_by_status => maps:map(fun(_Status, Ids) -> length(Ids) end, State#state.by_status)
  },
  {reply, {ok, Stats}, State};

handle_call(get_worker_count, _From, State) ->
  {reply, {ok, State#state.total_workers}, State};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast({unregister_worker, WorkerId}, State) ->
  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined ->
      {noreply, State};
    Worker ->
      NewWorkers = maps:remove(WorkerId, State#state.workers),

      CurrentByType = State#state.by_type,
      TypeWorkers = maps:get(Worker#worker.type, CurrentByType, []),
      NewByType = CurrentByType#{
        Worker#worker.type => lists:delete(WorkerId, TypeWorkers)
      },

      CurrentByStatus = State#state.by_status,
      StatusWorkers = maps:get(Worker#worker.status, CurrentByStatus, []),
      NewByStatus = CurrentByStatus#{
        Worker#worker.status => lists:delete(WorkerId, StatusWorkers)
      },

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
      {noreply, NewState}
  end;

handle_cast({update_load, WorkerId, Load}, State) ->
  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined ->
      {noreply, State};
    Worker ->
      UpdatedWorker = Worker#worker{current_load = Load},
      CurrentWorkers = State#state.workers,
      NewWorkers = CurrentWorkers#{WorkerId => UpdatedWorker},
      {noreply, State#state{workers = NewWorkers}}
  end;

handle_cast({mark_unhealthy, WorkerId, Reason}, State) ->
  case maps:get(WorkerId, State#state.workers, undefined) of
    undefined ->
      {noreply, State};
    Worker when Worker#worker.status =:= active ->

      %% FIX: Decouple metadata map update!
      OldMetadata = Worker#worker.metadata,
      NewMetadata = OldMetadata#{
        last_error => Reason,
        marked_unhealthy_at => erlang:system_time(millisecond)
      },

      UpdatedWorker = Worker#worker{
        status = unresponsive,
        metadata = NewMetadata
      },

      CurrentWorkers = State#state.workers,
      NewWorkers = CurrentWorkers#{WorkerId => UpdatedWorker},

      CurrentByStatus = State#state.by_status,
      ActiveWorkers = maps:get(active, CurrentByStatus, []),
      UnresponsiveWorkers = maps:get(unresponsive, CurrentByStatus, []),

      NewByStatus = CurrentByStatus#{
        active => lists:delete(WorkerId, ActiveWorkers),
        unresponsive => lists:usort([WorkerId | UnresponsiveWorkers])
      },

      CurrentUnhealthy = State#state.unhealthy_workers,
      NewUnhealthy = CurrentUnhealthy#{WorkerId => erlang:system_time(millisecond)},

      {noreply, State#state{
        workers = NewWorkers,
        by_status = NewByStatus,
        unhealthy_workers = NewUnhealthy,
        active_workers = State#state.active_workers - 1
      }};
    _ ->
      {noreply, State}
  end;

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(check_worker_health, State) ->
  Now = erlang:system_time(millisecond),
  Timeout = application:get_env(distriqueue, worker_heartbeat_timeout, 120000),

  lists:foreach(
    fun({WorkerId, Worker}) ->
      LastHB = Worker#worker.last_heartbeat,
      if
        Now - LastHB > Timeout andalso Worker#worker.status =:= active ->
          gen_server:cast(?MODULE, {mark_unhealthy, WorkerId, <<"Heartbeat timeout">>});
        true ->
          ok
      end
    end,
    maps:to_list(State#state.workers)
  ),

  erlang:send_after(30000, self(), check_worker_health),
  {noreply, State};

handle_info(cleanup_stale_workers, State) ->
  Now = erlang:system_time(millisecond),
  CleanupThreshold = application:get_env(distriqueue, worker_cleanup_timeout, 3600000),

  StaleWorkers = maps:filter(
    fun(_WorkerId, UnhealthySince) ->
      Now - UnhealthySince > CleanupThreshold
    end,
    State#state.unhealthy_workers
  ),

  lists:foreach(
    fun(WorkerId) ->
      gen_server:cast(?MODULE, {unregister_worker, WorkerId})
    end,
    maps:keys(StaleWorkers)
  ),

  erlang:send_after(3600000, self(), cleanup_stale_workers),
  {noreply, State};

handle_info(_Message, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

select_round_robin(Workers, State) ->
  Index = State#state.round_robin_counter rem length(Workers),
  lists:nth(Index + 1, Workers).

select_least_loaded(Workers) ->
  lists:foldl(
    fun(Worker, Acc) ->
      case Acc of
        undefined -> Worker;
        _ ->
          WCap = max(1, Worker#worker.capacity),
          ACap = max(1, Acc#worker.capacity),
          LoadRatio = Worker#worker.current_load / WCap,
          AccRatio = Acc#worker.current_load / ACap,
          if
            LoadRatio < AccRatio -> Worker;
            true -> Acc
          end
      end
    end,
    undefined,
    Workers
  ).

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
  {ok, _} = dq_worker_pool:start_link(),
  ok.

cleanup(_) ->
  gen_server:stop(worker_pool).

test_register_worker() ->
  ok = dq_worker_pool:register_worker(<<"worker1">>, <<"python">>, 5, 0),
  {ok, Worker} = dq_worker_pool:get_worker(<<"worker1">>),
  ?assertEqual(<<"worker1">>, Worker#worker.id),
  ?assertEqual(<<"python">>, Worker#worker.type),
  ?assertEqual(5, Worker#worker.capacity),
  ?assertEqual(0, Worker#worker.current_load).

test_get_worker() ->
  ok = dq_worker_pool:register_worker(<<"worker2">>, <<"java">>, 10, 2),
  {ok, Worker} = dq_worker_pool:get_worker(<<"worker2">>),
  ?assertEqual(<<"worker2">>, Worker#worker.id),
  ?assertEqual(10, Worker#worker.capacity),
  ?assertEqual(2, Worker#worker.current_load).

test_select_worker() ->
  ok = dq_worker_pool:register_worker(<<"worker3">>, <<"python">>, 5, 0),
  ok = dq_worker_pool:register_worker(<<"worker4">>, <<"python">>, 5, 3),
  ok = dq_worker_pool:register_worker(<<"worker5">>, <<"java">>, 10, 1),

  {ok, Selected} = dq_worker_pool:select_worker(<<"python">>),
  ?assert(lists:member(Selected, [<<"worker3">>, <<"worker4">>])),

  {ok, LeastLoaded} = dq_worker_pool:select_worker(<<"python">>, least_loaded),
  ?assertEqual(<<"worker3">>, LeastLoaded).

test_worker_health() ->
  ok = dq_worker_pool:register_worker(<<"worker6">>, <<"go">>, 5, 0),
  dq_worker_pool:update_worker_load(<<"worker6">>, 2),
  {ok, Worker} = dq_worker_pool:get_worker(<<"worker6">>),
  ?assertEqual(2, Worker#worker.current_load).

-endif.
