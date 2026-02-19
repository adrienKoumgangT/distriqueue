%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%% API Gateway HTTP Server
%%% @end
%%%-------------------------------------------------------------------
-module(http_server).
-author("adrien koumgang tegantchouang").
-behaviour(gen_server).

%% API
-export([start/0, start_link/0, stop/0]).

%% Cowboy callbacks
-export([init/2]).

%% Gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% Use the shared header instead of redefining the record
-include("distriqueue.hrl").

-record(state, {
  port = 8081,
  listener,
  routes = []
}).

%%% PUBLIC API %%%
start() ->
  start_link().

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
  gen_server:call(?MODULE, stop).

%%% GEN_SERVER CALLBACKS %%%
init([]) ->
  Port = application:get_env(distriqueue, http_port, 8081),
  {ok, #state{port = Port}, 0}.

handle_call(stop, _From, State) ->
  cowboy:stop_listener(State#state.listener),
  {stop, normal, ok, State};
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(timeout, State) ->
  Port = State#state.port,

  Routes = [
    {"/api/health", ?MODULE, health},
    {"/api/cluster/status", ?MODULE, cluster_status},
    {"/api/jobs/register", ?MODULE, register_job},
    {"/api/jobs/status", ?MODULE, update_job_status},
    {"/api/jobs/:id/status", ?MODULE, update_job_status},
    {"/api/jobs/:id/cancel", ?MODULE, cancel_job},
    {"/api/jobs", ?MODULE, list_jobs},
    {"/api/raft/status", ?MODULE, raft_status},
    {"/api/metrics", ?MODULE, metrics},
    {"/api/workers/heartbeat", ?MODULE, worker_heartbeat}
  ],

  Dispatch = cowboy_router:compile([{'_', Routes}]),

  {ok, Listener} = cowboy:start_clear(http_listener,
    [{port, Port}],
    #{env => #{dispatch => Dispatch}}
  ),

  lager:info("HTTP server started on port ~p", [Port]),

  {noreply, State#state{listener = Listener, routes = Routes}};
handle_info(_Info, State) ->
  {noreply, State}.

%%% COWBOY HANDLERS %%%
init(Req, health) ->
  {ok, handle_health(Req), health};

init(Req, cluster_status) ->
  {ok, handle_cluster_status(Req), cluster_status};

init(Req, register_job) ->
  {ok, handle_register_job(Req), register_job};

init(Req, update_job_status) ->
  {ok, handle_update_job_status(Req), update_job_status};

init(Req, cancel_job) ->
  {ok, handle_cancel_job(Req), cancel_job};

init(Req, list_jobs) ->
  {ok, handle_list_jobs(Req), list_jobs};

init(Req, raft_status) ->
  {ok, handle_raft_status(Req), raft_status};

init(Req, metrics) ->
  {ok, handle_metrics(Req), metrics};

init(Req, worker_heartbeat) ->
  {ok, handle_worker_heartbeat(Req), worker_heartbeat}.

handle_health(Req) ->
  Status = case job_registry:get_all_jobs() of
             {ok, _} -> <<"healthy">>;
             _ -> <<"degraded">>
           end,

  Response = jsx:encode(#{
    <<"status">> => Status,
    <<"timestamp">> => erlang:system_time(millisecond),
    <<"node">> => atom_to_binary(node(), utf8)
  }),

  cowboy_req:reply(200,
    #{<<"content-type">> => <<"application/json">>},
    Response, Req).

handle_cluster_status(Req) ->
  {Node, Status, RaftStatus} = distriqueue:cluster_status(),

  Response = jsx:encode(#{
    <<"node">> => atom_to_binary(Node, utf8),
    <<"cluster">> => Status,
    <<"raft">> => RaftStatus,
    <<"timestamp">> => erlang:system_time(millisecond)
  }),

  cowboy_req:reply(200,
    #{<<"content-type">> => <<"application/json">>},
    Response, Req).

handle_register_job(Req) ->
  {ok, Body, Req1} = cowboy_req:read_body(Req),

  try
    Job = jsx:decode(Body, [return_maps]),

    case distriqueue:register_job(Job) of
      ok ->
        Response = jsx:encode(#{
          <<"status">> => <<"accepted">>,
          <<"job_id">> => maps:get(<<"id">>, Job, <<"unknown">>)
        }),
        cowboy_req:reply(202,
          #{<<"content-type">> => <<"application/json">>},
          Response, Req1);
      Error ->
        ErrorMsg = list_to_binary(io_lib:format("~p", [Error])),
        Response = jsx:encode(#{
          <<"status">> => <<"error">>,
          <<"message">> => ErrorMsg
        }),
        cowboy_req:reply(400,
          #{<<"content-type">> => <<"application/json">>},
          Response, Req1)
    end
  catch
    _:_ ->
      cowboy_req:reply(400,
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(#{<<"error">> => <<"invalid_json">>}), Req1)
  end.

handle_update_job_status(Req) ->
  {ok, Body, Req1} = cowboy_req:read_body(Req),
  try
    Map = jsx:decode(Body, [return_maps]),

    JobId = case cowboy_req:binding(id, Req1) of
              undefined -> maps:get(<<"jobId">>, Map, maps:get(<<"id">>, Map, <<"unknown">>));
              Id -> Id
            end,

    StatusBin = maps:get(<<"status">>, Map, <<"pending">>),
    %% Safely fallback for both camelCase (Java) and snake_case (Python)
    WorkerId = maps:get(<<"workerId">>, Map, maps:get(<<"worker_id">>, Map, <<"unknown">>)),
    ResultMap = maps:get(<<"result">>, Map, undefined),

    StatusAtom = erlang:binary_to_atom(StatusBin, utf8),

    job_registry:update_job_result(JobId, StatusAtom, WorkerId, ResultMap),

    cowboy_req:reply(200,
      #{<<"content-type">> => <<"application/json">>},
      jsx:encode(#{<<"status">> => <<"updated">>}), Req1)
  catch
    Error:Reason ->
      lager:error("Status update failed: ~p:~p", [Error, Reason]),
      cowboy_req:reply(400,
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(#{<<"error">> => <<"invalid_request">>}), Req1)
  end.

handle_worker_heartbeat(Req) ->
  {ok, Body, Req1} = cowboy_req:read_body(Req),
  try
    Map = jsx:decode(Body, [return_maps]),
    WorkerId = maps:get(<<"workerId">>, Map, maps:get(<<"worker_id">>, Map, <<"unknown">>)),
    Capacity = maps:get(<<"capacity">>, Map, 10),
    CurrentLoad = maps:get(<<"currentLoad">>, Map, maps:get(<<"current_load">>, Map, 0)),

    gen_server:cast(router, {worker_heartbeat, WorkerId, Capacity, CurrentLoad}),

    cowboy_req:reply(200,
      #{<<"content-type">> => <<"application/json">>},
      jsx:encode(#{<<"status">> => <<"acknowledged">>}), Req1)
  catch
    _:_ ->
      cowboy_req:reply(400,
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(#{<<"error">> => <<"invalid_request">>}), Req1)
  end.

handle_cancel_job(Req) ->
  JobId = cowboy_req:binding(id, Req),

  distriqueue:cancel_job(JobId),

  cowboy_req:reply(200,
    #{<<"content-type">> => <<"application/json">>},
    jsx:encode(#{<<"status">> => <<"cancelled">>}), Req).

handle_list_jobs(Req) ->
  {ok, Jobs} = job_registry:get_all_jobs(),

  JobsJson = lists:map(
    fun(Job) ->
      #{
        <<"id">> => Job#job.id,
        <<"type">> => Job#job.type,
        <<"status">> => Job#job.status,
        <<"priority">> => Job#job.priority,
        <<"worker_id">> => Job#job.worker_id,
        <<"result">> => case Job#job.result of undefined -> null; Res -> Res end,
        <<"created_at">> => Job#job.created_at,
        <<"started_at">> => Job#job.started_at,
        <<"completed_at">> => Job#job.completed_at
      }
    end, Jobs),

  Response = jsx:encode(#{
    <<"jobs">> => JobsJson,
    <<"count">> => length(Jobs)
  }),

  cowboy_req:reply(200,
    #{<<"content-type">> => <<"application/json">>},
    Response, Req).

handle_raft_status(Req) ->
  case raft_fsm:get_state() of
    {follower, Term, Leader} ->
      Status = #{
        <<"role">> => <<"follower">>,
        <<"term">> => Term,
        <<"leader">> => atom_to_binary(Leader, utf8)
      };
    {candidate, Term} ->
      Status = #{
        <<"role">> => <<"candidate">>,
        <<"term">> => Term
      };
    {leader, Term} ->
      Status = #{
        <<"role">> => <<"leader">>,
        <<"term">> => Term
      }
  end,

  cowboy_req:reply(200,
    #{<<"content-type">> => <<"application/json">>},
    jsx:encode(Status), Req).

handle_metrics(Req) ->
  {ok, Jobs} = job_registry:get_all_jobs(),

  Stats = lists:foldl(
    fun(Job, Acc) ->
      Status = Job#job.status,
      Count = maps:get(Status, Acc, 0),
      Acc#{Status => Count + 1}
    end, #{}, Jobs),

  {ok, QueueStats} = router:get_queue_stats(),

  Response = jsx:encode(#{
    <<"jobs">> => Stats,
    <<"queues">> => QueueStats,
    <<"timestamp">> => erlang:system_time(millisecond)
  }),

  cowboy_req:reply(200,
    #{<<"content-type">> => <<"application/json">>},
    Response, Req).
