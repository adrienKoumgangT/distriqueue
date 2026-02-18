%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%% Metrics exporter for Prometheus format
%%% @end
%%%-------------------------------------------------------------------
-module(metrics_exporter).
-author("adrien koumgang tegantchouang").
-behaviour(gen_server).

%% API
-export([start/0,
  start_link/0,
  increment_counter/1,
  set_gauge/2,
  observe_histogram/2,
  get_metrics/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {
  metrics = #{} :: map(),
  port = 9100 :: integer(),
  listener :: term() | undefined
}).

%%% PUBLIC API %%%

start() ->
  gen_server:start({local, ?MODULE}, ?MODULE, [], []).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

increment_counter(Name) ->
  gen_server:cast(?MODULE, {increment, Name}).

set_gauge(Name, Value) ->
  gen_server:cast(?MODULE, {set_gauge, Name, Value}).

observe_histogram(Name, Value) ->
  gen_server:cast(?MODULE, {observe_histogram, Name, Value}).

get_metrics() ->
  gen_server:call(?MODULE, get_metrics).

%%% GEN_SERVER CALLBACKS %%%

init([]) ->
  Port = application:get_env(distriqueue, metrics_port, 9100),
  lager:info("Initializing metrics exporter on port ~p", [Port]),
  {ok, #state{port = Port}, 0}.

handle_call(get_metrics, _From, State) ->
  {reply, {ok, State#state.metrics}, State};

handle_call(_Request, _From, State) ->
  {reply, {error, unknown_request}, State}.

handle_cast({increment, Name}, State) ->
  CurrentMetrics = State#state.metrics,
  Counter = maps:get({counter, Name}, CurrentMetrics, 0),
  NewMetrics = CurrentMetrics#{{counter, Name} => Counter + 1},
  {noreply, State#state{metrics = NewMetrics}};

handle_cast({set_gauge, Name, Value}, State) ->
  CurrentMetrics = State#state.metrics,
  NewMetrics = CurrentMetrics#{{gauge, Name} => Value},
  {noreply, State#state{metrics = NewMetrics}};

handle_cast({observe_histogram, Name, Value}, State) ->
  CurrentMetrics = State#state.metrics,
  Histogram = maps:get({histogram, Name}, CurrentMetrics, []),
  NewHistogram = lists:sublist([Value | Histogram], 100),
  NewMetrics = CurrentMetrics#{{histogram, Name} => NewHistogram},
  {noreply, State#state{metrics = NewMetrics}};

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(timeout, State) ->
  Port = State#state.port,

  lager:info("Starting metrics exporter HTTP server on port ~p", [Port]),

  Opts = [binary,
    {active, false},
    {reuseaddr, true},
    {backlog, 1024},
    {ifaddr, {0,0,0,0}}],

  case gen_tcp:listen(Port, Opts) of
    {ok, ListenSocket} ->
      start_acceptors(ListenSocket, 10),
      lager:info("Metrics exporter started successfully on port ~p", [Port]),
      {noreply, State#state{listener = ListenSocket}};
    {error, Reason} ->
      lager:error("Failed to start metrics exporter on port ~p: ~p", [Port, Reason]),
      %% Don't crash the process, just try again in 5 seconds
      erlang:send_after(5000, self(), timeout),
      {noreply, State}
  end;

handle_info(_Info, State) ->
  {noreply, State}.

%%% INTERNAL FUNCTIONS %%%

start_acceptors(_ListenSocket, 0) ->
  ok;
start_acceptors(ListenSocket, N) ->
  spawn_link(fun() -> acceptor_loop(ListenSocket) end),
  start_acceptors(ListenSocket, N - 1).

acceptor_loop(ListenSocket) ->
  case gen_tcp:accept(ListenSocket) of
    {ok, Socket} ->
      spawn(fun() -> handle_client(Socket) end),
      acceptor_loop(ListenSocket);
    {error, closed} ->
      ok;
    {error, Reason} ->
      lager:error("Accept error: ~p", [Reason]),
      acceptor_loop(ListenSocket)
  end.

handle_client(Socket) ->
  case gen_tcp:recv(Socket, 0, 5000) of
    {ok, Request} ->
      Response = handle_request(Request),
      gen_tcp:send(Socket, Response),
      gen_tcp:close(Socket);
    {error, timeout} ->
      gen_tcp:close(Socket);
    {error, _} ->
      gen_tcp:close(Socket)
  end.

handle_request(<<"GET /metrics HTTP/1.1", _/binary>>) ->
  format_metrics();
handle_request(<<"GET /health HTTP/1.1", _/binary>>) ->
  "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nOK";
handle_request(<<"GET /", _/binary>>) ->
  "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"
  "<html><body><h1>DistriQueue Metrics</h1>"
  "<p><a href='/metrics'>Prometheus Metrics</a></p>"
  "<p><a href='/health'>Health Check</a></p>"
  "</body></html>";
handle_request(_) ->
  "HTTP/1.1 404 Not Found\r\n\r\nNot Found".

format_metrics() ->
  Header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\n\r\n",

  {ok, Metrics} = get_metrics(),

  MetricsLines = lists:map(
    fun({{Type, Name}, Value}) ->
      format_metric(Type, Name, Value)
    end, maps:to_list(Metrics)),

  SystemMetrics = format_system_metrics(),

  Header ++ lists:flatten([SystemMetrics | MetricsLines]).

format_metric(counter, Name, Value) ->
  io_lib:format("# HELP ~s Total count\n# TYPE ~s counter\n~s ~p\n", [Name, Name, Name, Value]);
format_metric(gauge, Name, Value) ->
  io_lib:format("# HELP ~s Current value\n# TYPE ~s gauge\n~s ~p\n", [Name, Name, Name, Value]);
format_metric(histogram, Name, Values) ->
  case Values of
    [] -> "";
    _ ->
      Count = length(Values),
      Sum = lists:sum(Values),
      Avg = Sum / Count,
      io_lib:format("# HELP ~s Histogram\n# TYPE ~s histogram\n~s_count ~p\n~s_sum ~p\n~s_avg ~p\n",
        [Name, Name, Name, Count, Name, Sum, Name, Avg])
  end.

format_system_metrics() ->
  ProcessCount = erlang:system_info(process_count),
  PortCount = erlang:system_info(port_count),
  Memory = erlang:memory(total),

  io_lib:format("# HELP erlang_vm_processes Number of processes\n"
  "# TYPE erlang_vm_processes gauge\n"
  "erlang_vm_processes ~p\n"
  "# HELP erlang_vm_ports Number of ports\n"
  "# TYPE erlang_vm_ports gauge\n"
  "erlang_vm_ports ~p\n"
  "# HELP erlang_vm_memory_bytes Memory usage in bytes\n"
  "# TYPE erlang_vm_memory_bytes gauge\n"
  "erlang_vm_memory_bytes ~p\n",
    [ProcessCount, PortCount, Memory]).
