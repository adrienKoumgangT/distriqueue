%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%% REST API Handlers for DistriQueue HTTP Server
%%% @end
%%%-------------------------------------------------------------------
-module(distriqueue_api).
-author("adrien koumgang tegantchouang").

%% Cowboy HTTP handlers
-export([init/2,
  handle_health/2,
  handle_cluster_status/2,
  handle_register_job/2,
  handle_update_job_status/2,
  handle_cancel_job/2,
  handle_get_job/2,
  handle_list_jobs/2,
  handle_raft_status/2,
  handle_worker_heartbeat/2,
  handle_metrics/2]).

%% Internal exports
-export([start/0, stop/0]).

-define(CONTENT_JSON, #{<<"content-type">> => <<"application/json">>}).
-define(CONTENT_TEXT, #{<<"content-type">> => <<"text/plain">>}).
-define(CONTENT_HTML, #{<<"content-type">> => <<"text/html">>}).

%%%===================================================================
%%% API - Start/Stop HTTP server
%%%===================================================================

%% @doc Start the HTTP server
start() ->
  Port = application:get_env(distriqueue, http_port, 8081),
  Dispatch = cowboy_router:compile([
    {'_', [
      {"/", ?MODULE, handle_root},
      {"/health", ?MODULE, handle_health},
      {"/api/health", ?MODULE, handle_health},
      {"/api/cluster/status", ?MODULE, handle_cluster_status},
      {"/api/jobs/register", ?MODULE, handle_register_job},
      {"/api/jobs/:id/status", ?MODULE, handle_update_job_status},
      {"/api/jobs/:id/cancel", ?MODULE, handle_cancel_job},
      {"/api/jobs/:id", ?MODULE, handle_get_job},
      {"/api/jobs", ?MODULE, handle_list_jobs},
      {"/api/raft/status", ?MODULE, handle_raft_status},
      {"/api/workers/heartbeat", ?MODULE, handle_worker_heartbeat},
      {"/api/metrics", ?MODULE, handle_metrics},
      {"/metrics", ?MODULE, handle_metrics}
    ]}
  ]),

  {ok, _} = cowboy:start_clear(distriqueue_http_listener,
    [{port, Port}],
    #{env => #{dispatch => Dispatch}}
  ),
  lager:info("DistriQueue HTTP API started on port ~p", [Port]),
  ok.

%% @doc Stop the HTTP server
stop() ->
  cowboy:stop_listener(distriqueue_http_listener),
  ok.

%%%===================================================================
%%% Cowboy Callback
%%%===================================================================

%% @doc Initialize Cowboy handler
init(Req, Handler) ->
  handle_request(Handler, Req).

handle_request(Handler, Req) ->
  try
    ?MODULE:Handler(Req, Handler)
  catch
    Class:Reason:Stacktrace ->
      lager:error("API handler ~p failed: ~p:~p~n~p",
        [Handler, Class, Reason, Stacktrace]),
      respond_error(500, <<"Internal Server Error">>, Req)
  end.

%%%===================================================================
%%% Root Handler
%%%===================================================================

%% @doc Handle root endpoint - HTML welcome page
handle_root(Req, State) ->
  Body = [
    "<!DOCTYPE html>",
    "<html>",
    "<head><title>DistriQueue API</title>",
    "<style>",
    "body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }",
    "h1 { color: #333; }",
    "h2 { color: #666; margin-top: 30px; }",
    "pre { background: #f4f4f4; padding: 10px; border-radius: 5px; }",
    "code { background: #f4f4f4; padding: 2px 5px; border-radius: 3px; }",
    ".endpoint { margin: 10px 0; padding: 10px; border-left: 3px solid #007bff; }",
    "</style>",
    "</head>",
    "<body>",
    "<h1>🚀 DistriQueue API</h1>",
    "<p>Distributed Job Scheduler - Erlang Orchestrator</p>",

    "<h2>System Status</h2>",
    "<div id='status'>",
    "<p><strong>Node:</strong> ", atom_to_binary(node(), utf8), "</p>",
    "<p><strong>Status:</strong> <span style='color: green;'>Online</span></p>",
    "</div>",

    "<h2>Available Endpoints</h2>",

    "<div class='endpoint'>",
    "<h3>GET /health</h3>",
    "<p>Health check endpoint</p>",
    "<pre>curl http://localhost:8081/health</pre>",
    "</div>",

    "<div class='endpoint'>",
    "<h3>GET /api/cluster/status</h3>",
    "<p>Cluster status information</p>",
    "<pre>curl http://localhost:8081/api/cluster/status</pre>",
    "</div>",

    "<div class='endpoint'>",
    "<h3>POST /api/jobs/register</h3>",
    "<p>Register a new job</p>",
    "<pre>curl -X POST http://localhost:8081/api/jobs/register \\",
    "\n  -H \"Content-Type: application/json\" \\",
    "\n  -d '{\"id\":\"job-123\",\"type\":\"calculate\",\"priority\":10,\"payload\":{\"numbers\":[1,2,3]}}'</pre>",
    "</div>",

    "<div class='endpoint'>",
    "<h3>PUT /api/jobs/:id/status</h3>",
    "<p>Update job status</p>",
    "<pre>curl -X PUT http://localhost:8081/api/jobs/job-123/status \\",
    "\n  -H \"Content-Type: application/json\" \\",
    "\n  -d '{\"status\":\"running\",\"worker_id\":\"worker-001\"}'</pre>",
    "</div>",

    "<div class='endpoint'>",
    "<h3>POST /api/jobs/:id/cancel</h3>",
    "<p>Cancel a job</p>",
    "<pre>curl -X POST http://localhost:8081/api/jobs/job-123/cancel</pre>",
    "</div>",

    "<div class='endpoint'>",
    "<h3>GET /api/jobs/:id</h3>",
    "<p>Get job details</p>",
    "<pre>curl http://localhost:8081/api/jobs/job-123</pre>",
    "</div>",

    "<div class='endpoint'>",
    "<h3>GET /api/jobs</h3>",
    "<p>List all jobs</p>",
    "<pre>curl http://localhost:8081/api/jobs</pre>",
    "</div>",

    "<div class='endpoint'>",
    "<h3>GET /api/raft/status</h3>",
    "<p>Raft consensus status</p>",
    "<pre>curl http://localhost:8081/api/raft/status</pre>",
    "</div>",

    "<div class='endpoint'>",
    "<h3>POST /api/workers/heartbeat</h3>",
    "<p>Worker heartbeat endpoint</p>",
    "<pre>curl -X POST http://localhost:8081/api/workers/heartbeat \\",
    "\n  -H \"Content-Type: application/json\" \\",
    "\n  -d '{\"worker_id\":\"worker-001\",\"capacity\":10,\"load\":5}'</pre>",
    "</div>",

    "<div class='endpoint'>",
    "<h3>GET /metrics</h3>",
    "<p>Prometheus metrics</p>",
    "<pre>curl http://localhost:8081/metrics</pre>",
    "</div>",

    "<h2>System Information</h2>",
    "<div id='info'>",
    "<p><strong>Erlang/OTP:</strong> ", erlang:system_info(otp_release), "</p>",
    "<p><strong>Processes:</strong> ", integer_to_list(erlang:system_info(process_count)), "</p>",
    "<p><strong>Memory:</strong> ", integer_to_list(erlang:memory(total) div 1024 div 1024), " MB</p>",
    "</div>",

    "<h2>Documentation</h2>",
    "<p>For complete API documentation, visit the <a href='https://github.com/yourusername/distriqueue'>GitHub repository</a>.</p>",

    "<hr>",
    "<p><em>DistriQueue - Distributed Systems Project, University of Pise 2026</em></p>",
    "</body>",
    "</html>"
  ],

  Req2 = cowboy_req:reply(200, ?CONTENT_HTML, Body, Req),
  {ok, Req2, State}.

%%%===================================================================
%%% Health Endpoint
%%%===================================================================

%% @doc Health check endpoint
handle_health(Req, State) ->
  % Check critical components
  JobRegistryStatus = case erlang:whereis(job_registry) of
                        undefined -> <<"down">>;
                        _Pid -> <<"up">>
                      end,

  RabbitMQStatus = case rabbitmq_client:status() of
                     {ok, _} -> <<"up">>;
                     _ -> <<"down">>
                   end,

  Response = jsx:encode(#{
    <<"status">> => <<"ok">>,
    <<"node">> => atom_to_binary(node(), utf8),
    <<"timestamp">> => erlang:system_time(millisecond),
    <<"uptime">> => erlang:system_time(millisecond) - erlang:system_info(start_time),
    <<"components">> => #{
      <<"job_registry">> => JobRegistryStatus,
      <<"rabbitmq">> => RabbitMQStatus
    }
  }),

  Req2 = cowboy_req:reply(200, ?CONTENT_JSON, Response, Req),
  {ok, Req2, State}.

%%%===================================================================
%%% Cluster Status Endpoint
%%%===================================================================

%% @doc Get cluster status
handle_cluster_status(Req, State) ->
  case distriqueue:cluster_status() of
    {Node, ClusterNodes, RaftStatus} ->
      ConnectedNodes = lists:map(
        fun({N, S}) ->
          #{
            <<"node">> => atom_to_binary(N, utf8),
            <<"status">> => atom_to_binary(S, utf8)
          }
        end, ClusterNodes),

      Response = jsx:encode(#{
        <<"node">> => atom_to_binary(Node, utf8),
        <<"connected_nodes">> => ConnectedNodes,
        <<"raft">> => format_raft_status(RaftStatus),
        <<"timestamp">> => erlang:system_time(millisecond)
      }),

      Req2 = cowboy_req:reply(200, ?CONTENT_JSON, Response, Req),
      {ok, Req2, State};
    Error ->
      respond_error(500, <<"Failed to get cluster status">>, Req, State)
  end.

%%%===================================================================
%%% Job Registration Endpoint
%%%===================================================================

%% @doc Register a new job
handle_register_job(Req, State) ->
  {ok, Body, Req2} = cowboy_req:read_body(Req),

  try
    Job = jsx:decode(Body, [return_maps]),

    % Validate required fields
    RequiredFields = [<<"id">>, <<"type">>, <<"priority">>],
    MissingFields = [F || F <- RequiredFields, not maps:is_key(F, Job)],

    case MissingFields of
      [] ->
        % Add default values if not present
        JobWithDefaults = Job#{
          <<"payload">> => maps:get(<<"payload">>, Job, #{}),
          <<"max_retries">> => maps:get(<<"max_retries">>, Job, 3),
          <<"execution_timeout">> => maps:get(<<"execution_timeout">>, Job, 300),
          <<"created_at">> => maps:get(<<"created_at">>, Job, erlang:system_time(millisecond))
        },

        case distriqueue:register_job(JobWithDefaults) of
          ok ->
            % Increment metrics
            metrics_exporter:increment_counter(<<"jobs_registered">>),

            Response = jsx:encode(#{
              <<"status">> => <<"accepted">>,
              <<"job_id">> => maps:get(<<"id">>, JobWithDefaults),
              <<"message">> => <<"Job registered successfully">>
            }),
            Req3 = cowboy_req:reply(202, ?CONTENT_JSON, Response, Req2),
            {ok, Req3, State};

          {error, Reason} ->
            respond_error(400,
              <<"Failed to register job: ", (atom_to_binary(Reason, utf8))/binary>>,
              Req2, State)
        end;
      _ ->
        MissingStr = string:join([binary_to_list(F) || F <- MissingFields], ", "),
        respond_error(400,
          <<"Missing required fields: ", (list_to_binary(MissingStr))/binary>>,
          Req2, State)
    end
  catch
    _:_ ->
      respond_error(400, <<"Invalid JSON payload">>, Req2, State)
  end.

%%%===================================================================
%%% Update Job Status Endpoint
%%%===================================================================

%% @doc Update job status
handle_update_job_status(Req, State) ->
  JobId = cowboy_req:binding(id, Req),
  {ok, Body, Req2} = cowboy_req:read_body(Req),

  try
    Update = jsx:decode(Body, [return_maps]),
    Status = maps:get(<<"status">>, Update, undefined),
    WorkerId = maps:get(<<"worker_id">>, Update, <<"unknown">>),

    case Status of
      undefined ->
        respond_error(400, <<"Missing status field">>, Req2, State);
      _ ->
        case job_registry:get_job(JobId) of
          {ok, Job} ->
            distriqueue:update_job_status(JobId, Status, WorkerId),

            % Update metrics
            case Status of
              <<"running">> ->
                metrics_exporter:increment_counter(<<"jobs_started">>);
              <<"completed">> ->
                metrics_exporter:increment_counter(<<"jobs_completed">>);
              <<"failed">> ->
                metrics_exporter:increment_counter(<<"jobs_failed">>);
              _ -> ok
            end,

            Response = jsx:encode(#{
              <<"status">> => <<"updated">>,
              <<"job_id">> => JobId,
              <<"new_status">> => Status
            }),
            Req3 = cowboy_req:reply(200, ?CONTENT_JSON, Response, Req2),
            {ok, Req3, State};

          not_found ->
            respond_error(404, <<"Job not found">>, Req2, State)
        end
    end
  catch
    _:_ ->
      respond_error(400, <<"Invalid JSON payload">>, Req2, State)
  end.

%%%===================================================================
%%% Cancel Job Endpoint
%%%===================================================================

%% @doc Cancel a job
handle_cancel_job(Req, State) ->
  JobId = cowboy_req:binding(id, Req),

  case job_registry:get_job(JobId) of
    {ok, Job} ->
      distriqueue:cancel_job(JobId),
      metrics_exporter:increment_counter(<<"jobs_cancelled">>),

      Response = jsx:encode(#{
        <<"status">> => <<"cancelled">>,
        <<"job_id">> => JobId,
        <<"message">> => <<"Job cancelled successfully">>
      }),
      Req2 = cowboy_req:reply(200, ?CONTENT_JSON, Response, Req),
      {ok, Req2, State};

    not_found ->
      respond_error(404, <<"Job not found">>, Req, State)
  end.

%%%===================================================================
%%% Get Job Endpoint
%%%===================================================================

%% @doc Get job details
handle_get_job(Req, State) ->
  JobId = cowboy_req:binding(id, Req),

  case job_registry:get_job(JobId) of
    {ok, Job} ->
      Response = jsx:encode(format_job(Job)),
      Req2 = cowboy_req:reply(200, ?CONTENT_JSON, Response, Req),
      {ok, Req2, State};

    not_found ->
      respond_error(404, <<"Job not found">>, Req, State)
  end.

%%%===================================================================
%%% List Jobs Endpoint
%%%===================================================================

%% @doc List all jobs
handle_list_jobs(Req, State) ->
  {ok, Jobs} = job_registry:get_all_jobs(),

  % Support filtering by status
  Qs = cowboy_req:parse_qs(Req),
  StatusFilter = proplists:get_value(<<"status">>, Qs),

  FilteredJobs = case StatusFilter of
                   undefined -> Jobs;
                   _ -> [J || J <- Jobs, element(3, J) =:= binary_to_atom(StatusFilter, utf8)]
                 end,

  % Support pagination
  Limit = case proplists:get_value(<<"limit">>, Qs) of
            undefined -> 100;
            L -> min(1000, binary_to_integer(L))
          end,
  Offset = case proplists:get_value(<<"offset">>, Qs) of
             undefined -> 0;
             O -> binary_to_integer(O)
           end,

  PaginatedJobs = lists:sublist(FilteredJobs, Offset + 1, Limit),

  Response = jsx:encode(#{
    <<"jobs">> => [format_job(J) || J <- PaginatedJobs],
    <<"total">> => length(FilteredJobs),
    <<"returned">> => length(PaginatedJobs),
    <<"limit">> => Limit,
    <<"offset">> => Offset
  }),

  Req2 = cowboy_req:reply(200, ?CONTENT_JSON, Response, Req),
  {ok, Req2, State}.

%%%===================================================================
%%% Raft Status Endpoint
%%%===================================================================

%% @doc Get Raft consensus status
handle_raft_status(Req, State) ->
  case raft_fsm:get_state() of
    {follower, Term, Leader} ->
      Status = #{
        <<"role">> => <<"follower">>,
        <<"term">> => Term,
        <<"leader">> => atom_to_binary(Leader, utf8),
        <<"log_size">> => length(raft_fsm:get_log())
      };
    {candidate, Term} ->
      Status = #{
        <<"role">> => <<"candidate">>,
        <<"term">> => Term,
        <<"log_size">> => length(raft_fsm:get_log())
      };
    {leader, Term} ->
      Status = #{
        <<"role">> => <<"leader">>,
        <<"term">> => Term,
        <<"log_size">> => length(raft_fsm:get_log())
      }
  end,

  Response = jsx:encode(Status),
  Req2 = cowboy_req:reply(200, ?CONTENT_JSON, Response, Req),
  {ok, Req2, State}.

%%%===================================================================
%%% Worker Heartbeat Endpoint
%%%===================================================================

%% @doc Receive worker heartbeat
handle_worker_heartbeat(Req, State) ->
  {ok, Body, Req2} = cowboy_req:read_body(Req),

  try
    Heartbeat = jsx:decode(Body, [return_maps]),

    % Validate required fields
    case maps:is_key(<<"worker_id">>, Heartbeat) of
      true ->
        WorkerId = maps:get(<<"worker_id">>, Heartbeat),
        WorkerType = maps:get(<<"worker_type">>, Heartbeat, <<"unknown">>),
        Capacity = maps:get(<<"capacity">>, Heartbeat, 10),
        CurrentLoad = maps:get(<<"current_load">>, Heartbeat, 0),

        % Register/update worker in pool
        dq_worker_pool:register_worker(WorkerId, WorkerType, Capacity, CurrentLoad),

        % Update metrics
        metrics_exporter:set_gauge(<<"worker_capacity">>, Capacity),
        metrics_exporter:set_gauge(<<"worker_load">>, CurrentLoad),

        Response = jsx:encode(#{
          <<"status">> => <<"ok">>,
          <<"worker_id">> => WorkerId,
          <<"timestamp">> => erlang:system_time(millisecond)
        }),

        Req3 = cowboy_req:reply(200, ?CONTENT_JSON, Response, Req2),
        {ok, Req3, State};

      false ->
        respond_error(400, <<"Missing worker_id field">>, Req2, State)
    end
  catch
    error:badarg ->
      respond_error(400, <<"Invalid JSON or missing fields">>, Req2, State);
    error:{badkey, Key} ->
      respond_error(400,
        <<"Missing required field: ", (atom_to_binary(Key, utf8))/binary>>,
        Req2, State);
    error:Error ->
      lager:error("Heartbeat processing error: ~p", [Error]),
      respond_error(400, <<"Invalid heartbeat payload">>, Req2, State);
    _:_ ->
      respond_error(400, <<"Invalid heartbeat payload">>, Req2, State)
  end.

%%%===================================================================
%%% Metrics Endpoint
%%%===================================================================

%% @doc Prometheus metrics endpoint
handle_metrics(Req, State) ->
  % Get job statistics
  {ok, Jobs} = job_registry:get_all_jobs(),

  % Count jobs by status
  JobCounts = lists:foldl(
    fun(Job, Acc) ->
      Status = element(3, Job),
      Count = maps:get(Status, Acc, 0),
      Acc#{Status => Count + 1}
    end, #{}, Jobs),

  % Get worker statistics
  {ok, Workers} = dq_worker_pool:get_all_workers(),

  % Format Prometheus metrics
  Metrics = [
    "# HELP distriqueue_jobs_total Total number of jobs",
    "# TYPE distriqueue_jobs_total counter",
    io_lib:format("distriqueue_jobs_total ~p", [length(Jobs)]),
    "",
    "# HELP distriqueue_jobs_by_status Jobs by status",
    "# TYPE distriqueue_jobs_by_status gauge",
    [io_lib:format("distriqueue_jobs_by_status{status=\"~s\"} ~p",
      [Status, Count]) || {Status, Count} <- maps:to_list(JobCounts)],
    "",
    "# HELP distriqueue_workers_total Total number of workers",
    "# TYPE distriqueue_workers_total gauge",
    io_lib:format("distriqueue_workers_total ~p", [length(Workers)]),
    "",
    "# HELP distriqueue_raft_role Current Raft role",
    "# TYPE distriqueue_raft_role gauge",
    case raft_fsm:get_state() of
      {follower, _, _} -> "distriqueue_raft_role{role=\"follower\"} 1";
      {candidate, _} -> "distriqueue_raft_role{role=\"candidate\"} 1";
      {leader, _} -> "distriqueue_raft_role{role=\"leader\"} 1"
    end,
    "",
    "# HELP distriqueue_raft_term Current Raft term",
    "# TYPE distriqueue_raft_term gauge",
    io_lib:format("distriqueue_raft_term ~p",
      [element(2, element(2, raft_fsm:get_state()))]),
    "",
    "# HELP erlang_vm_processes Number of Erlang processes",
    "# TYPE erlang_vm_processes gauge",
    io_lib:format("erlang_vm_processes ~p", [erlang:system_info(process_count)]),
    "",
    "# HELP erlang_vm_memory_bytes Memory usage in bytes",
    "# TYPE erlang_vm_memory_bytes gauge",
    io_lib:format("erlang_vm_memory_bytes ~p", [erlang:memory(total)])
  ],

  Body = string:join(lists:flatten(Metrics), "\n"),
  Req2 = cowboy_req:reply(200, ?CONTENT_TEXT, Body, Req),
  {ok, Req2, State}.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Format job record for JSON response
format_job(Job) when is_tuple(Job) ->
  #{
    <<"id">> => element(2, Job),
    <<"type">> => element(3, Job),
    <<"priority">> => element(4, Job),
    <<"status">> => atom_to_binary(element(5, Job), utf8),
    <<"worker_id">> => element(6, Job),
    <<"payload">> => element(7, Job),
    <<"result">> => element(8, Job),
    <<"error_message">> => element(9, Job),
    <<"retry_count">> => element(10, Job),
    <<"max_retries">> => element(11, Job),
    <<"execution_timeout">> => element(12, Job),
    <<"created_at">> => element(13, Job),
    <<"started_at">> => element(14, Job),
    <<"completed_at">> => element(15, Job),
    <<"metadata">> => element(16, Job)
  }.

%% @doc Format Raft status for response
format_raft_status({follower, Term, Leader}) ->
  #{
    <<"role">> => <<"follower">>,
    <<"term">> => Term,
    <<"leader">> => atom_to_binary(Leader, utf8)
  };
format_raft_status({candidate, Term}) ->
  #{
    <<"role">> => <<"candidate">>,
    <<"term">> => Term
  };
format_raft_status({leader, Term}) ->
  #{
    <<"role">> => <<"leader">>,
    <<"term">> => Term
  }.

%% @doc Send error response
respond_error(Code, Message, Req) ->
  respond_error(Code, Message, Req, undefined).

respond_error(Code, Message, Req, State) ->
  Response = jsx:encode(#{
    <<"error">> => true,
    <<"status_code">> => Code,
    <<"message">> => Message,
    <<"timestamp">> => erlang:system_time(millisecond)
  }),
  Req2 = cowboy_req:reply(Code, ?CONTENT_JSON, Response, Req),
  {ok, Req2, State}.
