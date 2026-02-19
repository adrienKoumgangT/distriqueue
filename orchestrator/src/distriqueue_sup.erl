%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%% Main Supervisor for the DistriQueue Orchestrator
%%% @end
%%%-------------------------------------------------------------------
-module(distriqueue_sup).
-author("adrien koumgang tegantchouang").
-behaviour(supervisor).

%% API
-export([start_link/0, init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  SupFlags = #{
    strategy => one_for_one,
    intensity => 5,
    period => 10
  },

  Children = [
    %% Metrics and Health (Infrastructure first)
    #{
      id => metrics_exporter,
      start => {metrics_exporter, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },
    #{
      id => health_monitor,
      start => {health_monitor, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },

    %% Consensus and Data
    #{
      id => raft_fsm,
      start => {raft_fsm, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },
    #{
      id => job_registry,
      start => {job_registry, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },

    %% Resource Management
    #{
      id => dq_worker_pool,
      start => {dq_worker_pool, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },

    %% External Communication (RabbitMQ)
    #{
      id => rabbitmq_client,
      start => {rabbitmq_client, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },

    %% Routing Logic
    #{
      id => router,
      start => {router, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },

    %% API Layer (Start last so background services are ready)
    #{
      id => http_server,
      start => {http_server, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    }
  ],

  {ok, {SupFlags, Children}}.
