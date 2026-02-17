%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%%
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
  SupFlags = #{strategy => one_for_one,
    intensity => 5,
    period => 10},

  Children = [
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

    #{
      id => health_monitor,
      start => {health_monitor, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },

    #{
      id => router,
      start => {router, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },

    #{
      id => dq_worker_pool,
      start => {dq_worker_pool, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },

    #{
      id => rabbitmq_client,
      start => {rabbitmq_client, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },

    #{
      id => metrics_exporter,
      start => {metrics_exporter, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    }
  ],

  {ok, {SupFlags, Children}}.