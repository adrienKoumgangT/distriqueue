%%%-------------------------------------------------------------------
%%% @author adrien koumgang tegantchouang
%%% @copyright (C) 2026, University of Pise
%%% @doc
%%% Raft Consensus Algorithm Implementation
%%% @end
%%%-------------------------------------------------------------------
-module(raft_fsm).
-author("adrien koumgang tegantchouang").
-behaviour(gen_statem).

%% API
-export([start_link/0,
  get_state/0,
  get_log/0,
  propose/1]).

%% Java RPC handler
-export([get_state_rpc/1]).

%% gen_statem callbacks
-export([init/1,
  callback_mode/0,
  terminate/3,
  code_change/4]).

%% State functions - MUST export ALL states used in next_state
-export([follower/3,
  candidate/3,
  leader/3]).

-record(state, {
  current_term = 0,
  voted_for = none,
  log = [],
  commit_index = 0,
  last_applied = 0,
  peers = [],
  leader_id = none,
  election_timer_ref,
  heartbeat_timer_ref,
  next_index = #{},
  match_index = #{},
  votes = 0           % Track votes received
}).

%%% PUBLIC API %%%
start_link() ->
  gen_statem:start_link({local, ?MODULE}, ?MODULE, [], []).

get_state() ->
  gen_statem:call(?MODULE, get_state).

get_log() ->
  gen_statem:call(?MODULE, get_log).

propose(Command) ->
  gen_statem:call(?MODULE, {propose, Command}).

get_state_rpc([status]) ->
  case get_state() of
    {follower, Term, LeaderId} ->
      {ok, {follower, Term, LeaderId}};
    {candidate, Term} ->
      {ok, {candidate, Term}};
    {leader, Term} ->
      {ok, {leader, Term}}
  end.

%%% GEN_STATEM CALLBACKS %%%
init([]) ->
  process_flag(trap_exit, true),
  Peers = case application:get_env(distriqueue, raft_peers) of
            {ok, PeerList} ->
              lists:map(fun list_to_atom/1, PeerList);
            undefined ->
              []
          end,
  lager:info("Raft FSM initialized with peers: ~p", [Peers]),
  State = #state{peers = Peers},
  {ok, follower, State, [{state_timeout, random_election_timeout(), election_timeout}]}.

callback_mode() -> state_functions.

terminate(_Reason, _State, _Data) ->
  ok.

code_change(_OldVsn, State, Data, _Extra) ->
  {ok, State, Data}.

%%% ============================================================
%%% FOLLOWER STATE - COMPLETE CALLBACKS
%%% ============================================================

%% Handle state timeout (election timeout)
follower(state_timeout, election_timeout, State) ->
  lager:info("Election timeout, becoming candidate for term ~p",
    [State#state.current_term + 1]),
  NewTerm = State#state.current_term + 1,

  % Request votes from all peers
  LastLogIndex = length(State#state.log),
  LastLogTerm = get_last_log_term(State#state.log),

  lists:foreach(
    fun(Peer) ->
      gen_statem:cast({?MODULE, Peer},
        {request_vote_rpc, node(), NewTerm, LastLogIndex, LastLogTerm})
    end, State#state.peers),

  {next_state, candidate,
    State#state{current_term = NewTerm, voted_for = node(), votes = 1},
    [{state_timeout, random_election_timeout(), election_timeout}]};

%% Handle synchronous calls
follower({call, From}, get_state, State) ->
  {keep_state, State,
    [{reply, From, {follower, State#state.current_term, State#state.leader_id}}]};

follower({call, From}, get_log, State) ->
  {keep_state, State, [{reply, From, State#state.log}]};

follower({call, From}, {propose, Command}, State) ->
  % Follower should forward to leader
  case State#state.leader_id of
    none ->
      {keep_state, State,
        [{reply, From, {error, no_leader}}]};
    Leader ->
      % Forward to leader
      gen_statem:call({?MODULE, Leader}, {propose, Command}),
      {keep_state, State,
        [{reply, From, {forwarded, Leader}}]}
  end;

%% Handle asynchronous casts
follower(cast, {request_vote_rpc, CandidateId, Term, LastLogIndex, LastLogTerm}, State) ->
  % Grant vote if candidate's log is at least as up-to-date
  CanVote = (Term > State#state.current_term) orelse
    (Term =:= State#state.current_term andalso
      (State#state.voted_for =:= none orelse
        State#state.voted_for =:= CandidateId)) andalso
      (LastLogIndex >= length(State#state.log)) andalso
      (LastLogTerm >= get_last_log_term(State#state.log)),

  Reply = {vote_granted, node(), State#state.current_term, CanVote},
  gen_statem:cast({?MODULE, CandidateId}, {request_vote_reply, Reply}),

  NewState = if
               CanVote andalso Term > State#state.current_term ->
                 State#state{current_term = Term, voted_for = CandidateId};
               CanVote ->
                 State#state{voted_for = CandidateId};
               true ->
                 State
             end,
  {keep_state, NewState};

follower(cast, {append_entries_rpc, LeaderId, Term, PrevLogIndex,
  PrevLogTerm, Entries, LeaderCommit}, State) ->
  % Check if log matches at PrevLogIndex
  LogOk = case PrevLogIndex of
            0 -> true;
            _ when PrevLogIndex =< length(State#state.log) ->
              {PrevTerm, _} = lists:nth(PrevLogIndex, State#state.log),
              PrevTerm =:= PrevLogTerm;
            _ -> false
          end,

  Success = (Term >= State#state.current_term) andalso LogOk,

  if
    Success ->
      % Update term
      NewTerm = max(State#state.current_term, Term),

      % Append new entries (remove conflicting entries)
      NewLog = append_entries(State#state.log, PrevLogIndex, Entries),

      % Update commit index
      NewCommitIndex = min(LeaderCommit, length(NewLog)),

      NewState = State#state{
        current_term = NewTerm,
        leader_id = LeaderId,
        log = NewLog,
        commit_index = NewCommitIndex
      },

      % Apply committed entries
      apply_committed_entries(NewState),

      {keep_state, NewState,
        [{reply, {LeaderId, node()},
          {append_entries_reply, NewTerm, true, length(NewLog)}}]};
    true ->
      {keep_state, State,
        [{reply, {LeaderId, node()},
          {append_entries_reply, State#state.current_term, false, length(State#state.log)}}]}
  end;

%% Handle info messages
follower(info, Message, State) ->
  lager:warning("Follower received unknown info: ~p", [Message]),
  {keep_state, State};

%% Catch-all for any other events
follower(EventType, EventContent, State) ->
  lager:debug("Follower received unhandled event: ~p, ~p", [EventType, EventContent]),
  {keep_state, State}.

%%% ============================================================
%%% CANDIDATE STATE - COMPLETE CALLBACKS
%%% ============================================================

%% Handle state timeout (election timeout)
candidate(state_timeout, election_timeout, State) ->
  lager:info("Candidate election timeout, starting new election for term ~p",
    [State#state.current_term + 1]),
  NewTerm = State#state.current_term + 1,

  LastLogIndex = length(State#state.log),
  LastLogTerm = get_last_log_term(State#state.log),

  lists:foreach(
    fun(Peer) ->
      gen_statem:cast({?MODULE, Peer},
        {request_vote_rpc, node(), NewTerm, LastLogIndex, LastLogTerm})
    end, State#state.peers),

  {next_state, candidate,
    State#state{current_term = NewTerm, voted_for = node(), votes = 1},
    [{state_timeout, random_election_timeout(), election_timeout}]};

%% Handle synchronous calls
candidate({call, From}, get_state, State) ->
  {keep_state, State,
    [{reply, From, {candidate, State#state.current_term}}]};

candidate({call, From}, get_log, State) ->
  {keep_state, State, [{reply, From, State#state.log}]};

candidate({call, From}, {propose, _Command}, State) ->
  % Candidate cannot accept proposals until elected
  {keep_state, State,
    [{reply, From, {error, no_leader}}]};

%% Handle asynchronous casts
candidate(cast, {request_vote_reply, {vote_granted, VoterId, Term, true}},
    #state{current_term = Term, peers = Peers, votes = Votes} = State) ->
  NewVotes = Votes + 1,
  lager:info("Received vote from ~p, total votes: ~p", [VoterId, NewVotes]),

  VotesNeeded = (length(Peers) + 1) div 2 + 1,  % Majority of cluster

  if
    NewVotes >= VotesNeeded ->
      lager:info("Received majority votes, becoming leader for term ~p", [Term]),
      {next_state, leader,
        State#state{leader_id = node(), votes = 0},
        [{state_timeout, 150, heartbeat}]};
    true ->
      {keep_state, State#state{votes = NewVotes}}
  end;

candidate(cast, {request_vote_reply, {vote_granted, _VoterId, _Term, false}}, State) ->
  % Vote denied, ignore
  {keep_state, State};

candidate(cast, {request_vote_rpc, CandidateId, Term, LastLogIndex, LastLogTerm}, State) ->
  %% If the incoming candidate has a higher term, we must step down and evaluate their vote
  if
    Term > State#state.current_term ->
      lager:info("Candidate ~p stepping down to follower for higher term ~p from ~p",
        [node(), Term, CandidateId]),

      %% Check log freshness
      CanVote = (LastLogIndex >= length(State#state.log)) andalso
        (LastLogTerm >= get_last_log_term(State#state.log)),

      Reply = {vote_granted, node(), Term, CanVote},
      gen_statem:cast({?MODULE, CandidateId}, {request_vote_reply, Reply}),

      NewState = if
                   CanVote -> State#state{current_term = Term, voted_for = CandidateId};
                   true -> State#state{current_term = Term, voted_for = none}
                 end,

      {next_state, follower, NewState, [{state_timeout, random_election_timeout(), election_timeout}]};

  %% If the term is the same or lower, reject the vote (we voted for ourselves)
    true ->
      Reply = {vote_granted, node(), State#state.current_term, false},
      gen_statem:cast({?MODULE, CandidateId}, {request_vote_reply, Reply}),
      {keep_state, State}
  end;

candidate(cast, {append_entries_rpc, LeaderId, Term, PrevLogIndex,
  PrevLogTerm, Entries, LeaderCommit}, State) ->
  % If we receive append entries from a leader with higher term, step down
  if
    Term >= State#state.current_term ->
      lager:info("Candidate stepping down to follower, leader ~p term ~p",
        [LeaderId, Term]),

      % Process the append entries as follower
      NewState = State#state{
        current_term = Term,
        leader_id = LeaderId
      },

      % Re-call the append entries handler as follower
      follower(cast, {append_entries_rpc, LeaderId, Term, PrevLogIndex,
        PrevLogTerm, Entries, LeaderCommit}, NewState);
    true ->
      {keep_state, State}
  end;

%% Handle info messages
candidate(info, Message, State) ->
  lager:warning("Candidate received unknown info: ~p", [Message]),
  {keep_state, State};

%% Catch-all for any other events
candidate(EventType, EventContent, State) ->
  lager:debug("Candidate received unhandled event: ~p, ~p", [EventType, EventContent]),
  {keep_state, State}.

%%% ============================================================
%%% LEADER STATE - COMPLETE CALLBACKS
%%% ============================================================

%% Handle state timeout (heartbeat)
leader(state_timeout, heartbeat, State) ->
  % Send heartbeat to all followers
  lists:foreach(
    fun(Peer) ->
      gen_statem:cast({?MODULE, Peer},
        {append_entries_rpc, node(), State#state.current_term,
          0, 0, [], State#state.commit_index})
    end, State#state.peers),

  {keep_state, State, [{state_timeout, 150, heartbeat}]};

%% Handle synchronous calls
leader({call, From}, get_state, State) ->
  {keep_state, State,
    [{reply, From, {leader, State#state.current_term}}]};

leader({call, From}, get_log, State) ->
  {keep_state, State, [{reply, From, State#state.log}]};

leader({call, From}, {propose, Command}, State) ->
  % Append command to log
  NewLogEntry = {State#state.current_term, Command},
  NewLog = State#state.log ++ [NewLogEntry],

  % Replicate to followers (in real implementation, wait for majority)
  replicate_log(State#state.peers, State#state.current_term, NewLog),

  NewState = State#state{log = NewLog},
  {keep_state, NewState,
    [{reply, From, {ok, length(NewLog)}}]};

%% Handle asynchronous casts
leader(cast, {append_entries_reply, FromNode, Term, Success, _MatchIndex}, State) ->
  if
    Success ->
      % Update match index for follower
      % In real implementation, track match index and commit when majority
      lager:debug("Follower ~p replicated successfully", [FromNode]);
    true ->
      % If failure due to term, step down
      if
        Term > State#state.current_term ->
          lager:info("Leader stepping down, higher term ~p from ~p",
            [Term, FromNode]),
          {next_state, follower,
            State#state{current_term = Term, leader_id = none},
            [{state_timeout, random_election_timeout(), election_timeout}]};
        true ->
          % Decrement nextIndex and retry (simplified)
          lager:debug("Follower ~p replication failed", [FromNode])
      end
  end,
  {keep_state, State};

leader(cast, {request_vote_rpc, CandidateId, Term, _LastLogIndex, _LastLogTerm}, State) ->
  % Leader should not grant votes if term is not higher
  if
    Term > State#state.current_term ->
      lager:info("Leader stepping down, candidate ~p has higher term ~p",
        [CandidateId, Term]),
      {next_state, follower,
        State#state{current_term = Term, leader_id = none},
        [{state_timeout, random_election_timeout(), election_timeout}]};
    true ->
      Reply = {vote_granted, node(), State#state.current_term, false},
      gen_statem:cast({?MODULE, CandidateId}, {request_vote_reply, Reply}),
      {keep_state, State}
  end;

%% Handle info messages
leader(info, Message, State) ->
  lager:warning("Leader received unknown info: ~p", [Message]),
  {keep_state, State};

%% Catch-all for any other events
leader(EventType, EventContent, State) ->
  lager:debug("Leader received unhandled event: ~p, ~p", [EventType, EventContent]),
  {keep_state, State}.

%%% ============================================================
%%% HELPER FUNCTIONS
%%% ============================================================

random_election_timeout() ->
  1500 + rand:uniform(1500). % 1.5 to 3s

get_last_log_term([]) -> 0;
get_last_log_term(Log) -> element(1, lists:last(Log)).

append_entries(Log, PrevLogIndex, []) ->
  lists:sublist(Log, PrevLogIndex);
append_entries(Log, PrevLogIndex, Entries) ->
  % Keep entries up to PrevLogIndex, then append new entries
  lists:sublist(Log, PrevLogIndex) ++ Entries.

apply_committed_entries(#state{log = Log, commit_index = CommitIndex,
  last_applied = LastApplied} = State) ->
  if
    CommitIndex > LastApplied ->
      EntriesToApply = lists:sublist(Log, LastApplied + 1,
        CommitIndex - LastApplied),
      lists:foreach(
        fun({_Term, Command}) ->
          apply_command(Command)
        end, EntriesToApply),
      State#state{last_applied = CommitIndex};
    true ->
      State
  end.

apply_command({register_job, Job}) ->
  job_registry:register_job(Job);
apply_command({update_status, JobId, Status, WorkerId}) ->
  job_registry:update_status(JobId, Status, WorkerId);
apply_command({cancel_job, JobId}) ->
  job_registry:cancel_job(JobId);
apply_command(_) ->
  ok.

replicate_log([], _Term, _Log) ->
  ok;
replicate_log(Peers, Term, Log) ->
  lists:foreach(
    fun(Peer) ->
      PrevLogIndex = length(Log) - 1,
      PrevLogTerm = case PrevLogIndex of
                      0 -> 0;
                      _ -> element(1, lists:nth(PrevLogIndex, Log))
                    end,
      Entries = lists:sublist(Log, PrevLogIndex + 1),

      gen_statem:cast({?MODULE, Peer},
        {append_entries_rpc, node(), Term,
          PrevLogIndex, PrevLogTerm, Entries, length(Log)})
    end, Peers).
