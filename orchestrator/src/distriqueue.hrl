%%%-------------------------------------------------------------------
%%% Shared Record Definitions for DistriQueue
%%%-------------------------------------------------------------------

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

