# DistriQueue Orchestrator

Distributed job scheduler orchestrator written in Erlang/OTP. It maintains job state, routes work to RabbitMQ queues, tracks worker health, and coordinates leader election with a Raft-style FSM.

## Features
- Job registry with status tracking, worker assignment, and cancelation
- Raft-style leader election for cluster coordination
- Priority-based routing to RabbitMQ queues
- HTTP API for cluster status and job management
- Prometheus-style metrics exporter and JSON metrics endpoint
- Worker pool management with heartbeat and load tracking

## Architecture
- `distriqueue` application boots the supervision tree and starts the HTTP server
- `raft_fsm` manages leader election and log replication state
- `job_registry` stores job metadata and broadcasts updates between nodes
- `router` maps job priority to queues and assigns workers
- `rabbitmq_client` publishes jobs to RabbitMQ and consumes work
- `health_monitor` collects local and remote node health
- `metrics_exporter` serves Prometheus metrics on a separate port

## Requirements
- Erlang/OTP 26
- rebar3
- RabbitMQ 3.12+ accessible from the orchestrator nodes

## Quickstart
```sh
rebar3 compile
rebar3 shell
```

The HTTP API listens on port 8081 by default.

## Configuration
Default values live in `config/sys.config` and `config/vm.args`.

Key settings:
- `node_name` and `cookie` for Erlang distribution
- `rabbitmq_host`, `rabbitmq_port`, `rabbitmq_username`, `rabbitmq_password`
- `http_port` for the API server
- `metrics_port` for the Prometheus exporter
- `raft_peers` list of peer node names

Update `config/sys.config` for environment-specific values. Release builds read `config/vm.args` for node name and cookie.

## HTTP API
Base URL: `http://localhost:8081`

- `GET /api/health`
- `GET /api/cluster/status`
- `POST /api/jobs/register`
- `PUT /api/jobs/:id/status`
- `POST /api/jobs/:id/cancel`
- `GET /api/jobs`
- `GET /api/raft/status`
- `GET /api/metrics` (JSON)

Example job registration:
```sh
curl -X POST http://localhost:8081/api/jobs/register \
  -H "Content-Type: application/json" \
  -d '{"id":"job-123","type":"calculate","priority":10,"payload":{"numbers":[1,2,3]}}'
```

Update job status:
```sh
curl -X PUT http://localhost:8081/api/jobs/job-123/status \
  -H "Content-Type: application/json" \
  -d '{"status":"running","worker_id":"worker-001"}'
```

Cancel a job:
```sh
curl -X POST http://localhost:8081/api/jobs/job-123/cancel
```

List jobs:
```sh
curl http://localhost:8081/api/jobs
```

Cluster status:
```sh
curl http://localhost:8081/api/cluster/status
```

Raft status:
```sh
curl http://localhost:8081/api/raft/status
```

Health check:
```sh
curl http://localhost:8081/api/health
```

JSON metrics snapshot:
```sh
curl http://localhost:8081/api/metrics
```

## Minimal OpenAPI Spec
```yaml
openapi: 3.0.3
info:
  title: DistriQueue Orchestrator API
  version: 1.0.0
servers:
  - url: http://localhost:8081
paths:
  /api/health:
    get:
      summary: Health check
      responses:
        "200":
          description: OK
  /api/cluster/status:
    get:
      summary: Cluster status
      responses:
        "200":
          description: OK
  /api/jobs/register:
    post:
      summary: Register a job
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/JobRegistration"
      responses:
        "202":
          description: Accepted
  /api/jobs/{id}/status:
    put:
      summary: Update job status
      parameters:
        - in: path
          name: id
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/JobStatusUpdate"
      responses:
        "200":
          description: Updated
  /api/jobs/{id}/cancel:
    post:
      summary: Cancel job
      parameters:
        - in: path
          name: id
          required: true
          schema:
            type: string
      responses:
        "200":
          description: Cancelled
  /api/jobs:
    get:
      summary: List jobs
      responses:
        "200":
          description: OK
  /api/raft/status:
    get:
      summary: Raft status
      responses:
        "200":
          description: OK
  /api/metrics:
    get:
      summary: Metrics snapshot (JSON)
      responses:
        "200":
          description: OK
components:
  schemas:
    JobRegistration:
      type: object
      required: [id, type]
      properties:
        id:
          type: string
        type:
          type: string
        priority:
          type: integer
          minimum: 1
        payload:
          type: object
    JobStatusUpdate:
      type: object
      required: [status, worker_id]
      properties:
        status:
          type: string
          enum: [pending, running, completed, failed, cancelled]
        worker_id:
          type: string
```

## Metrics
- Prometheus exporter: `http://localhost:9100/metrics`
- Exporter health: `http://localhost:9100/health`

The HTTP API also exposes a JSON metrics snapshot at `/api/metrics`.

## Docker
Build:
```sh
docker build -f docker/Dockerfile -t distriqueue-orchestrator .
```

Run:
```sh
docker run --rm -p 8081:8081 -p 9100:9100 distriqueue-orchestrator
```

## Release
```sh
rebar3 as prod tar
_build/prod/rel/distriqueue/bin/distriqueue foreground
```

## Notes
- Ensure RabbitMQ is reachable and has permissions to create the `jobs.exchange` and `job.*` queues.
- Cluster nodes must share the same cookie and be able to connect over the Erlang distribution ports.
