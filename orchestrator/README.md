# DistriQueue Orchestrator

Erlang/OTP orchestrator for DistriQueue. It accepts jobs over HTTP, stores in-memory job state, routes jobs to RabbitMQ priority queues, tracks worker heartbeats, and exposes cluster/raft/metrics endpoints.

## What It Does
- Accepts job registration and status updates through HTTP.
- Routes jobs to RabbitMQ queues by priority:
  - `job.high` (priority >= 10)
  - `job.medium` (priority >= 5)
  - `job.low` (priority < 5)
- Maintains job state in `job_registry`.
- Tracks worker capacity/load via heartbeat updates.
- Runs a Raft-style FSM for leader/candidate/follower state.
- Exposes JSON metrics and a Prometheus metrics listener.

## Architecture
Main OTP application: `distriqueue`

Core modules:
- `distriqueue_sup`: supervisor tree.
- `http_server`: HTTP API on `http_port` (default `8081`).
- `job_registry`: in-memory job store and indexes.
- `router`: priority routing + worker assignment.
- `rabbitmq_client`: AMQP publishing/consuming and queue setup.
- `dq_worker_pool`: worker registry and selection logic.
- `raft_fsm`: Raft-like consensus state machine.
- `health_monitor`: node/local health checks.
- `metrics_exporter`: Prometheus-style metrics listener.

## Requirements
- Erlang/OTP 26
- `rebar3`
- RabbitMQ reachable from orchestrator (`amqp://<host>:5672`)

## Local Run
```bash
rebar3 get-deps
rebar3 compile
rebar3 shell
```

Default API base URL:
- `http://localhost:8081`

Prometheus metrics listener (from current `config/sys.config`):
- `http://localhost:9101/metrics`

## Configuration
Primary runtime config is in `config/sys.config`.

Current defaults in this repo:
- `node_name`: `orchestrator@Adrien0`
- `cookie`: `VANQLBWBSYTBKENFPEWC`
- `rabbitmq_host`: `10.2.1.11`
- `rabbitmq_port`: `5672`
- `rabbitmq_username`: `admin`
- `rabbitmq_password`: `admin`
- `http_port`: `8081`
- `metrics_port`: `9101`
- `raft_peers`: `["orchestrator@Adrien1.local"]`

VM/distribution settings are in `config/vm.args` (node name, cookie, process limits, etc).

## 2-VM Deployment (10.2.1.11 / 10.2.1.12)
Use long node names with IP-based host parts on both machines.

Recommended node identities:
- VM1 (`10.2.1.11`): `orchestrator@10.2.1.11`
- VM2 (`10.2.1.12`): `orchestrator@10.2.1.12`

Use the same cookie on both VMs.

`config/vm.args` on `10.2.1.11`:
```bash
-name orchestrator@10.2.1.11
-setcookie VANQLBWBSYTBKENFPEWC
```

`config/vm.args` on `10.2.1.12`:
```bash
-name orchestrator@10.2.1.12
-setcookie VANQLBWBSYTBKENFPEWC
```

`config/sys.config` on `10.2.1.11` (`distriqueue` section):
```erlang
{node_name, "orchestrator@10.2.1.11"},
{raft_peers, ["orchestrator@10.2.1.12"]}
```

`config/sys.config` on `10.2.1.12` (`distriqueue` section):
```erlang
{node_name, "orchestrator@10.2.1.12"},
{raft_peers, ["orchestrator@10.2.1.11"]}
```

Build and run on each VM:
```bash
rebar3 get-deps
rebar3 compile
rebar3 shell
```

Quick connectivity check from the Erlang shell:
```erlang
net_adm:ping('orchestrator@10.2.1.12').
```
Expected result: `pong` (and symmetric check from VM2 to VM1).

## HTTP API
Routes currently served by `src/http_server.erl`:

- `GET /api/health`
- `GET /api/cluster/status`
- `POST /api/jobs/register`
- `PUT /api/jobs/:id/status`
- `POST /api/jobs/status` (job id can be in JSON body)
- `POST /api/jobs/:id/cancel`
- `GET /api/jobs`
- `GET /api/raft/status`
- `GET /api/metrics` (JSON snapshot)
- `POST /api/workers/heartbeat`

### Example: Register Job
```bash
curl -X POST http://localhost:8081/api/jobs/register \
  -H "Content-Type: application/json" \
  -d '{
    "id":"job-123",
    "type":"calculate",
    "priority":10,
    "payload":{"numbers":[1,2,3]}
  }'
```

### Example: Update Job Status
```bash
curl -X PUT http://localhost:8081/api/jobs/job-123/status \
  -H "Content-Type: application/json" \
  -d '{
    "status":"completed",
    "workerId":"worker-001",
    "result":{"sum":6}
  }'
```

### Example: Worker Heartbeat
```bash
curl -X POST http://localhost:8081/api/workers/heartbeat \
  -H "Content-Type: application/json" \
  -d '{
    "worker_id":"worker-001",
    "worker_type":"calculate",
    "capacity":10,
    "current_load":2
  }'
```

## Metrics
Two metrics surfaces exist:

- API JSON snapshot:
  - `GET /api/metrics` on API port (`8081` by default)
- Prometheus endpoint:
  - `GET /metrics` on `metrics_port` (`9101` in current config)
  - `GET /health` on metrics port

## RabbitMQ Topology
Declared by `rabbitmq_client`:
- Exchange: `jobs.exchange` (`direct`, durable)
- Queues:
  - `job.high` (`x-max-priority=10`)
  - `job.medium` (`x-max-priority=5`)
  - `job.low` (`x-max-priority=1`)

Status publishing uses:
- Exchange: `status.exchange`
- Routing key: `status.update`

## Docker
Build:
```bash
docker build -f docker/Dockerfile -t distriqueue-orchestrator .
```

Run:
```bash
docker run --rm -p 8081:8081 -p 9100:9100 distriqueue-orchestrator
```

Note: Dockerfile currently exposes `9100`, while `config/sys.config` sets metrics to `9101`. Keep these aligned for your target environment.

## Release Build
```bash
rebar3 as prod tar
_build/prod/rel/distriqueue/bin/distriqueue foreground
```

## Utility Script
`build-orchestrator.sh` exists for local rebuilds, but it is aggressive (`pkill`, `_build` cleanup, lockfile removal). Review before using in shared/dev environments.
