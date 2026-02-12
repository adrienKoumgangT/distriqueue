%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(distriqueue).
-author("adrien koumgang tegantchouang").
-behaviour(application).

%% API
-export([start/2, stop/1,
  cluster_status/0,
  register_job/1,
  update_job_status/3,
  cancel_job/1]).

%% Java RPC handlers
-export([cluster_status_rpc/1,
  register_job_rpc/1,
  update_job_status_rpc/1,
  cancel_job_rpc/1]).

start(_StartType, _StartArgs) ->
  lager:info("Starting DistriQueue application"),

  % Read configuration
  NodeName = get_env(node_name),
  Cookie = get_env(cookie),
  RaftPeers = get_env(raft_peers, []),

  lager:info("Node: ~p, Cookie: ~p, Raft Peers: ~p",
    [NodeName, Cookie, RaftPeers]),

  % Set cookie for distribution
  erlang:set_cookie(node(), list_to_atom(Cookie)),

  % Start supervisor
  case distriqueue_sup:start_link() of
    {ok, Pid} ->
      % Connect to Raft peers
      connect_to_peers(RaftPeers),

      % Start HTTP server
      http_server:start(),

      % Start metrics exporter
      metrics_exporter:start(),

      lager:info("DistriQueue started successfully on node ~p", [node()]),
      {ok, Pid};
    Error ->
      lager:error("Failed to start DistriQueue: ~p", [Error]),
      Error
  end.

stop(_State) ->
  lager:info("Stopping DistriQueue application"),
  ok.

%% Public API
cluster_status() ->
  Nodes = nodes(),
  Status = lists:map(
    fun(Node) ->
      case net_adm:ping(Node) of
        pong -> {Node, active};
        pang -> {Node, down}
      end
    end, Nodes),

  RaftStatus = case raft_fsm:get_state() of
                 {follower, Term, Leader} ->
                   {follower, Term, Leader};
                 {candidate, Term} ->
                   {candidate, Term};
                 {leader, Term} ->
                   {leader, Term}
               end,

  {node(), Status, RaftStatus}.

register_job(Job) ->
  job_registry:register_job(Job).

update_job_status(JobId, Status, WorkerId) ->
  job_registry:update_status(JobId, Status, WorkerId).

cancel_job(JobId) ->
  job_registry:cancel_job(JobId).

%% Java RPC handlers
cluster_status_rpc([]) ->
  {ok, cluster_status()}.

register_job_rpc([Job]) ->
  case register_job(Job) of
    ok -> {ok, <<"Job registered">>};
    Error -> {error, Error}
  end.

update_job_status_rpc([{update_status, JobId, Status, WorkerId, _Timestamp}]) ->
  update_job_status(JobId, Status, WorkerId),
  {ok, <<"Status updated">>}.

cancel_job_rpc([{cancel_job, JobId}]) ->
  cancel_job(JobId),
  {ok, <<"Job cancelled">>}.

%% Internal functions
get_env(Key) ->
  case application:get_env(distriqueue, Key) of
    {ok, Value} -> Value;
    undefined -> undefined
  end.

get_env(Key, Default) ->
  case application:get_env(distriqueue, Key) of
    {ok, Value} -> Value;
    undefined -> Default
  end.

connect_to_peers([]) ->
  ok;
connect_to_peers([Peer | Rest]) ->
  case net_adm:ping(list_to_atom(Peer)) of
    pong ->
      lager:info("Connected to peer ~p", [Peer]);
    pang ->
      lager:warning("Failed to connect to peer ~p", [Peer])
  end,
  connect_to_peers(Rest).
