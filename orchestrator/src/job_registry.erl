%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University Of Pise
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(job_registry).
-author("adrien komgang tegantchouang").
-behaviour(gen_server).

%% API
-export([start_link/0,
  register_job/1,
  update_status/3,
  cancel_job/1,
  get_job/1,
  get_all_jobs/0,
  find_jobs_by_status/1,
  find_jobs_by_worker/1]).

%% Java RPC handlers
-export([register_job_rpc/1,
  update_status_rpc/1,
  cancel_job_rpc/1,
  get_job_rpc/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(job, {
  id,
  type,
  priority,
  status = pending,
  worker_id = none,
  payload,
  result,
  error_message,
  retry_count = 0,
  max_retries = 3,
  execution_timeout = 300,
  created_at,
  started_at,
  completed_at,
  metadata = #{}
}).

-record(state, {
  jobs = #{},
  crdt_state = orddict:new(),
  by_status = #{},
  by_worker = #{}
}).

%%% PUBLIC API %%%
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

register_job(Job) ->
  gen_server:call(?MODULE, {register_job, Job}).

update_status(JobId, Status, WorkerId) ->
  gen_server:cast(?MODULE, {update_status, JobId, Status, WorkerId}).

cancel_job(JobId) ->
  gen_server:cast(?MODULE, {cancel_job, JobId}).

get_job(JobId) ->
  gen_server:call(?MODULE, {get_job, JobId}).

get_all_jobs() ->
  gen_server:call(?MODULE, get_all_jobs).

find_jobs_by_status(Status) ->
  gen_server:call(?MODULE, {find_by_status, Status}).

find_jobs_by_worker(WorkerId) ->
  gen_server:call(?MODULE, {find_by_worker, WorkerId}).

%%% JAVA RPC HANDLERS %%%
register_job_rpc([{register_job, JobId, JobType, Priority, Payload, Timeout, MaxRetries}]) ->
  Job = #{
    id => JobId,
    type => JobType,
    priority => Priority,
    payload => Payload,
    execution_timeout => Timeout,
    max_retries => MaxRetries,
    created_at => erlang:system_time(millisecond)
  },
  register_job(Job).

update_status_rpc([{update_status, JobId, Status, WorkerId, _Timestamp}]) ->
  update_status(JobId, Status, WorkerId),
  {ok, <<"Status updated">>}.

cancel_job_rpc([{cancel_job, JobId}]) ->
  cancel_job(JobId),
  {ok, <<"Job cancelled">>}.

get_job_rpc([JobId]) ->
  case get_job(JobId) of
    {ok, Job} -> {ok, Job};
    not_found -> {error, <<"Job not found">>}
  end.

%%% GEN_SERVER CALLBACKS %%%
init([]) ->
  {ok, #state{}}.

handle_call({register_job, JobMap}, _From, State) ->
  JobId = maps:get(id, JobMap),

  Job = #job{
    id = JobId,
    type = maps:get(type, JobMap),
    priority = maps:get(priority, JobMap, 5),
    payload = maps:get(payload, JobMap, #{}),
    max_retries = maps:get(max_retries, JobMap, 3),
    execution_timeout = maps:get(execution_timeout, JobMap, 300),
    created_at = maps:get(created_at, JobMap, erlang:system_time(millisecond)),
    metadata = maps:get(metadata, JobMap, #{})
  },

  % Update job map
  NewJobs = State#state.jobs#{JobId => Job},

  % Update status index
  Status = Job#job.status,
  StatusJobs = maps:get(Status, State#state.by_status, []),
  NewByStatus = State#state.by_status#{Status => [JobId | StatusJobs]},

  % Update CRDT state
  Timestamp = erlang:system_time(microsecond),
  NewCRDT = orddict:store(JobId, {Timestamp, added}, State#state.crdt_state),

  % Route to appropriate queue
  router:route_job(Job),

  % Broadcast to other nodes
  broadcast_job_update(Job),

  NewState = State#state{
    jobs = NewJobs,
    by_status = NewByStatus,
    crdt_state = NewCRDT
  },

  lager:info("Registered job ~p of type ~p with priority ~p",
    [JobId, Job#job.type, Job#job.priority]),

  {reply, ok, NewState};

handle_call({get_job, JobId}, _From, State) ->
  case maps:get(JobId, State#state.jobs, not_found) of
    not_found -> {reply, not_found, State};
    Job -> {reply, {ok, Job}, State}
  end;

handle_call(get_all_jobs, _From, State) ->
  Jobs = maps:values(State#state.jobs),
  {reply, {ok, Jobs}, State};

handle_call({find_by_status, Status}, _From, State) ->
  JobIds = maps:get(Status, State#state.by_status, []),
  Jobs = lists:map(
    fun(JobId) ->
      maps:get(JobId, State#state.jobs)
    end, JobIds),
  {reply, {ok, Jobs}, State};

handle_call({find_by_worker, WorkerId}, _From, State) ->
  WorkerJobs = maps:get(WorkerId, State#state.by_worker, []),
  Jobs = lists:map(
    fun(JobId) ->
      maps:get(JobId, State#state.jobs)
    end, WorkerJobs),
  {reply, {ok, Jobs}, State}.

handle_cast({update_status, JobId, Status, WorkerId}, State) ->
  case maps:get(JobId, State#state.jobs, not_found) of
    not_found ->
      {noreply, State};
    Job ->
      OldStatus = Job#job.status,
      OldWorkerId = Job#job.worker_id,

      % Update job
      Now = erlang:system_time(millisecond),
      UpdatedJob = case Status of
                     running ->
                       Job#job{
                         status = running,
                         worker_id = WorkerId,
                         started_at = Now
                       };
                     completed ->
                       Job#job{
                         status = completed,
                         worker_id = WorkerId,
                         completed_at = Now
                       };
                     failed ->
                       Job#job{
                         status = failed,
                         worker_id = WorkerId,
                         completed_at = Now
                       };
                     _ ->
                       Job#job{
                         status = Status,
                         worker_id = WorkerId
                       }
                   end,

      % Update job map
      NewJobs = State#state.jobs#{JobId => UpdatedJob},

      % Update status index
      NewByStatus = update_index(State#state.by_status,
        OldStatus, Status, JobId),

      % Update worker index
      NewByWorker = update_worker_index(State#state.by_worker,
        OldWorkerId, WorkerId, JobId),

      NewState = State#state{
        jobs = NewJobs,
        by_status = NewByStatus,
        by_worker = NewByWorker
      },

      % Broadcast update
      broadcast_job_update(UpdatedJob),

      lager:info("Job ~p status changed from ~p to ~p, worker: ~p",
        [JobId, OldStatus, Status, WorkerId]),

      {noreply, NewState}
  end;

handle_cast({cancel_job, JobId}, State) ->
  case maps:get(JobId, State#state.jobs, not_found) of
    not_found ->
      {noreply, State};
    Job ->
      % Remove from queue
      rabbitmq_client:cancel_job(JobId),

      % Update job
      UpdatedJob = Job#job{
        status = cancelled,
        completed_at = erlang:system_time(millisecond)
      },

      NewJobs = State#state.jobs#{JobId => UpdatedJob},

      % Update status index
      OldStatus = Job#job.status,
      NewByStatus = update_index(State#state.by_status,
        OldStatus, cancelled, JobId),

      NewState = State#state{
        jobs = NewJobs,
        by_status = NewByStatus
      },

      broadcast_job_update(UpdatedJob),

      lager:info("Job ~p cancelled", [JobId]),

      {noreply, NewState}
  end;

handle_cast({sync_job, Job}, State) ->
  % Received from another node
  JobId = Job#job.id,
  NewJobs = State#state.jobs#{JobId => Job},

  % Update indices
  Status = Job#job.status,
  StatusJobs = maps:get(Status, State#state.by_status, []),
  NewByStatus = State#state.by_status#{Status => [JobId | StatusJobs]},

  WorkerId = Job#job.worker_id,
  WorkerJobs = maps:get(WorkerId, State#state.by_worker, []),
  NewByWorker = State#state.by_worker#{WorkerId => [JobId | WorkerJobs]},

  NewState = State#state{
    jobs = NewJobs,
    by_status = NewByStatus,
    by_worker = NewByWorker
  },

  {noreply, NewState}.

handle_info(_Info, State) ->
  {noreply, State}.

%%% INTERNAL FUNCTIONS %%%
update_index(ByStatus, OldStatus, NewStatus, JobId) ->
  % Remove from old status
  ByStatus1 = case OldStatus of
                undefined -> ByStatus;
                _ ->
                  OldJobs = maps:get(OldStatus, ByStatus, []),
                  ByStatus#{OldStatus => lists:delete(JobId, OldJobs)}
              end,

  % Add to new status
  NewJobs = maps:get(NewStatus, ByStatus1, []),
  ByStatus1#{NewStatus => [JobId | NewJobs]}.

update_worker_index(ByWorker, OldWorkerId, NewWorkerId, JobId) ->
  % Remove from old worker
  ByWorker1 = case OldWorkerId of
                none -> ByWorker;
                _ ->
                  OldJobs = maps:get(OldWorkerId, ByWorker, []),
                  ByWorker#{OldWorkerId => lists:delete(JobId, OldJobs)}
              end,

  % Add to new worker
  NewJobs = maps:get(NewWorkerId, ByWorker1, []),
  ByWorker1#{NewWorkerId => [JobId | NewJobs]}.

broadcast_job_update(Job) ->
  Nodes = [N || N <- nodes(), N /= node()],
  lists:foreach(
    fun(Node) ->
      gen_server:cast({?MODULE, Node}, {sync_job, Job})
    end, Nodes).
