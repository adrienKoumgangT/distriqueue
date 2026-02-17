%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%% RabbitMQ Client for DistriQueue
%%% @end
%%%-------------------------------------------------------------------
-module(rabbitmq_client).
-author("adrien koumgang tegantchouang").
-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").

%% API
-export([start_link/0,
  publish_job/2,
  cancel_job/1,
  consume_jobs/1,
  get_queue_info/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {
  connection,
  channel,
  queues = #{} :: map(),
  consumers = #{} :: map()
}).

%%% PUBLIC API %%%
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

publish_job(Queue, Job) ->
  gen_server:call(?MODULE, {publish_job, Queue, Job}).

cancel_job(JobId) ->
  gen_server:cast(?MODULE, {cancel_job, JobId}).

consume_jobs(Queue) ->
  gen_server:cast(?MODULE, {consume_jobs, Queue, self()}).

get_queue_info(Queue) ->
  gen_server:call(?MODULE, {get_queue_info, Queue}).

%%% GEN_SERVER CALLBACKS %%%
init([]) ->
  case connect_to_rabbitmq() of
    {ok, Connection, Channel} ->
      setup_infrastructure(Channel),
      start_consumers(Channel),
      {ok, #state{connection = Connection, channel = Channel}};
    Error ->
      lager:error("Failed to connect to RabbitMQ: ~p", [Error]),
      {stop, Error}
  end.

handle_call({publish_job, Queue, Job}, _From, State) ->
  try
    JobJson = job_to_json(Job),

    %% Ensure we can extract priority whether Job is a map or a proplist
    Priority = case is_map(Job) of
                 true -> maps:get(priority, Job, maps:get(<<"priority">>, Job, 5));
                 false -> 5
               end,

    Props = #'P_basic'{
      delivery_mode = 2, % persistent
      priority = priority_to_amqp(Priority)
    },

    BasicPublish = #'basic.publish'{
      exchange = <<"jobs.exchange">>,
      routing_key = Queue
    },

    ok = amqp_channel:cast(State#state.channel, BasicPublish,
      #amqp_msg{props = Props, payload = JobJson}),

    %% Try to extract ID for logging safely
    JobId = case is_map(Job) of
              true -> maps:get(id, Job, maps:get(<<"id">>, Job, <<"unknown">>));
              false -> <<"unknown">>
            end,

    lager:debug("Published job ~p to queue ~p", [JobId, Queue]),
    {reply, ok, State}
  catch
    Error:Reason ->
      lager:error("Failed to publish job: ~p:~p", [Error, Reason]),
      {reply, {error, Reason}, State}
  end;

handle_call({get_queue_info, Queue}, _From, State) ->
  try
    #'queue.declare_ok'{message_count = Count} =
      amqp_channel:call(State#state.channel,
        #'queue.declare'{queue = Queue, passive = true}),
    {reply, {ok, #{count => Count}}, State}
  catch
    _:_ -> {reply, {error, not_found}, State}
  end;
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast({cancel_job, JobId}, State) ->
  lager:info("Job cancellation requested for ~p", [JobId]),
  {noreply, State};

handle_cast({consume_jobs, Queue, ConsumerPid}, State) ->
  Tag = erlang:binary_to_atom(Queue, utf8),

  amqp_channel:call(State#state.channel,
    #'basic.consume'{queue = Queue, no_ack = false, consumer_tag = Tag}),

  CurrentConsumers = State#state.consumers,
  NewConsumers = CurrentConsumers#{Tag => ConsumerPid},

  {noreply, State#state{consumers = NewConsumers}};
handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(#'basic.consume_ok'{consumer_tag = Tag}, State) ->
  lager:debug("Started consuming from queue ~p", [Tag]),
  {noreply, State};

handle_info({#'basic.deliver'{delivery_tag = DeliveryTag, consumer_tag = Tag},
  #amqp_msg{payload = Body}}, State) ->
  Channel = State#state.channel,
  spawn(fun() -> process_message(Tag, DeliveryTag, Body, Channel) end),
  {noreply, State};

handle_info(#'basic.cancel_ok'{consumer_tag = Tag}, State) ->
  CurrentConsumers = State#state.consumers,
  NewConsumers = maps:remove(Tag, CurrentConsumers),
  {noreply, State#state{consumers = NewConsumers}};
handle_info(_Info, State) ->
  {noreply, State}.

%%% INTERNAL FUNCTIONS %%%
connect_to_rabbitmq() ->
  Host = get_env(rabbitmq_host, "10.2.1.11"),
  Port = get_env(rabbitmq_port, 5672),
  Username = get_env(rabbitmq_username, "admin"),
  Password = get_env(rabbitmq_password, "admin"),

  Params = #amqp_params_network{
    host = Host,
    port = Port,
    username = list_to_binary(Username),
    password = list_to_binary(Password),
    heartbeat = 60
  },

  case amqp_connection:start(Params) of
    {ok, Connection} ->
      case amqp_connection:open_channel(Connection) of
        {ok, Channel} -> {ok, Connection, Channel};
        ErrChannel -> ErrChannel
      end;
    ErrConn -> ErrConn
  end.

setup_infrastructure(Channel) ->
  amqp_channel:call(Channel,
    #'exchange.declare'{
      exchange = <<"jobs.exchange">>,
      type = <<"direct">>,
      durable = true
    }),

  Queues = [
    {<<"job.high">>, 10},
    {<<"job.medium">>, 5},
    {<<"job.low">>, 1}
  ],

  lists:foreach(
    fun({Queue, Priority}) ->
      Args = #{<<"x-max-priority">> => Priority},
      amqp_channel:call(Channel,
        #'queue.declare'{
          queue = Queue,
          durable = true,
          arguments = Args
        }),

      amqp_channel:call(Channel,
        #'queue.bind'{
          queue = Queue,
          exchange = <<"jobs.exchange">>,
          routing_key = Queue
        })
    end, Queues).

start_consumers(Channel) ->
  Queues = [<<"job.high">>, <<"job.medium">>, <<"job.low">>],
  lists:foreach(
    fun(Queue) ->
      amqp_channel:call(Channel,
        #'basic.consume'{queue = Queue, no_ack = false})
    end, Queues).

process_message(Tag, DeliveryTag, Body, Channel) ->
  try
    Job = jsx:decode(Body),
    JobId = maps:get(<<"id">>, Job, <<"unknown">>),

    lager:debug("Processing job ~p from queue ~p", [JobId, Tag]),

    case router:assign_worker(Job) of
      {ok, WorkerId} ->
        job_registry:update_status(JobId, running, WorkerId),
        amqp_channel:cast(Channel,
          #'basic.ack'{delivery_tag = DeliveryTag}),
        lager:info("Job ~p assigned to worker ~p", [JobId, WorkerId]);

      {error, Reason} ->
        amqp_channel:cast(Channel,
          #'basic.reject'{delivery_tag = DeliveryTag, requeue = true}),
        lager:warning("Failed to assign job ~p: ~p", [JobId, Reason])
    end
  catch
    ErrorType:ErrorReason ->
      lager:error("Error processing message: ~p:~p", [ErrorType, ErrorReason]),
      amqp_channel:cast(Channel,
        #'basic.reject'{delivery_tag = DeliveryTag, requeue = false})
  end.

job_to_json(Job) ->
  jsx:encode(Job).

priority_to_amqp(Priority) when is_integer(Priority), Priority >= 10 -> 10;
priority_to_amqp(Priority) when is_integer(Priority), Priority >= 5 -> 5;
priority_to_amqp(_) -> 1.

get_env(Key, Default) ->
  case application:get_env(distriqueue, Key) of
    {ok, Value} -> Value;
    undefined -> Default
  end.
