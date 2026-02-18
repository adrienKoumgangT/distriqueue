%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University Of Pise
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-author("adrien koumgang tegantchouang").


%%% Shared Record Definitions for DistriQueue

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

