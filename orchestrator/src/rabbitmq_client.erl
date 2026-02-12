%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(rabbitmq_client).
-author("adrien koumgang tegantchouang").
-behaviour(gen_server).

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
  queues = #{},
  consumers = #{}
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
  % Connect to RabbitMQ
  case connect_to_rabbitmq() of
    {ok, Connection, Channel} ->
      % Declare exchanges and queues
      setup_infrastructure(Channel),

      % Start consuming from queues
      start_consumers(Channel),

      {ok, #state{connection = Connection, channel = Channel}};
    Error ->
      lager:error("Failed to connect to RabbitMQ: ~p", [Error]),
      {stop, Error}
  end.

handle_call({publish_job, Queue, Job}, _From, State) ->
  try
    % Convert job to JSON
    JobJson = job_to_json(Job),

    % Publish with appropriate priority
    Priority = maps:get(priority, Job, 5),
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

    lager:debug("Published job ~p to queue ~p",
      [maps:get(id, Job), Queue]),

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
  end.

handle_cast({cancel_job, JobId}, State) ->
  % In a real implementation, we would need to track job messages
  % and reject/nack them. For now, just log.
  lager:info("Job cancellation requested for ~p", [JobId]),
  {noreply, State};

handle_cast({consume_jobs, Queue, ConsumerPid}, State) ->
  % Subscribe to queue
  Tag = erlang:binary_to_atom(Queue, utf8),

  amqp_channel:subscribe(State#state.channel,
    #'basic.consume'{queue = Queue, no_ack = false, consumer_tag = Tag},
    self()),

  NewConsumers = State#state.consumers#{Tag => ConsumerPid},

  {noreply, State#state{consumers = NewConsumers}}.

handle_info(#'basic.consume_ok'{consumer_tag = Tag}, State) ->
  lager:debug("Started consuming from queue ~p", [Tag]),
  {noreply, State};

handle_info({#'basic.deliver'{delivery_tag = DeliveryTag, consumer_tag = Tag},
  #amqp_msg{payload = Body}}, State) ->
  % Process incoming message
  spawn(fun() -> process_message(Tag, DeliveryTag, Body, State) end),
  {noreply, State};

handle_info(#'basic.cancel_ok'{consumer_tag = Tag}, State) ->
  NewConsumers = maps:remove(Tag, State#state.consumers),
  {noreply, State#state{consumers = NewConsumers}}.

%%% INTERNAL FUNCTIONS %%%
connect_to_rabbitmq() ->
  Host = get_env(rabbitmq_host, "rabbitmq1"),
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

  {ok, Connection} = amqp_connection:start(Params),
  {ok, Channel} = amqp_connection:open_channel(Connection),

  {ok, Connection, Channel}.

setup_infrastructure(Channel) ->
  % Declare exchange
  amqp_channel:call(Channel,
    #'exchange.declare'{
      exchange = <<"jobs.exchange">>,
      type = <<"direct">>,
      durable = true
    }),

  % Declare queues with priorities
  Queues = [
    {<<"job.high">>, 10},
    {<<"job.medium">>, 5},
    {<<"job.low">>, 1}
  ],

  lists:foreach(
    fun({Queue, Priority}) ->
      Args = [{<<"x-max-priority">>, signedint, Priority}],
      amqp_channel:call(Channel,
        #'queue.declare'{
          queue = Queue,
          durable = true,
          arguments = Args
        }),

      % Bind to exchange
      amqp_channel:call(Channel,
        #'queue.bind'{
          queue = Queue,
          exchange = <<"jobs.exchange">>,
          routing_key = Queue
        })
    end, Queues).

start_consumers(Channel) ->
  % Subscribe to all job queues
  Queues = [<<"job.high">>, <<"job.medium">>, <<"job.low">>],

  lists:foreach(
    fun(Queue) ->
      amqp_channel:subscribe(Channel,
        #'basic.consume'{queue = Queue, no_ack = false},
        self())
    end, Queues).

process_message(Tag, DeliveryTag, Body, State) ->
  try
    % Parse JSON
    Job = jsx:decode(Body, [return_maps]),
    JobId = maps:get(<<"id">>, Job),

    lager:debug("Processing job ~p from queue ~p", [JobId, Tag]),

    % Assign to worker
    case router:assign_worker(Job) of
      {ok, WorkerId} ->
        % Update job status
        job_registry:update_status(JobId, running, WorkerId),

        % Acknowledge message
        amqp_channel:cast(State#state.channel,
          #'basic.ack'{delivery_tag = DeliveryTag}),

        lager:info("Job ~p assigned to worker ~p", [JobId, WorkerId]);

      {error, Reason} ->
        % Reject message (will be requeued)
        amqp_channel:cast(State#state.channel,
          #'basic.reject'{delivery_tag = DeliveryTag, requeue = true}),

        lager:warning("Failed to assign job ~p: ~p", [JobId, Reason])
    end

  catch
    Error:Reason ->
      lager:error("Error processing message: ~p:~p", [Error, Reason]),
      % Reject without requeue (send to dead letter)
      amqp_channel:cast(State#state.channel,
        #'basic.reject'{delivery_tag = DeliveryTag, requeue = false})
  end.

job_to_json(Job) ->
  jsx:encode(Job).

priority_to_amqp(Priority) when Priority >= 10 -> 10;
priority_to_amqp(Priority) when Priority >= 5 -> 5;
priority_to_amqp(_) -> 1.

get_env(Key, Default) ->
  case application:get_env(distriqueue, Key) of
    {ok, Value} -> Value;
    undefined -> Default
  end.
