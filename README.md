# DistriQueue

DistriQueue is a distributed job-processing platform built around:
- a Java/Spring Boot API gateway (`gateway/`)
- an Erlang/OTP orchestrator (`orchestrator/`)
- worker services in Python and Java (`workers/python-worker/`, `workers/java-worker/`)
- RabbitMQ for job queues and status fan-out
- H2 and Redis for persistence/cache on the gateway side

## Architecture Overview

1. A client submits jobs to the Gateway (`/api/jobs`).
2. The Gateway persists jobs (H2), publishes to RabbitMQ priority queues, and registers jobs with the orchestrator over HTTP.
3. Workers consume `job.high`, `job.medium`, `job.low`, execute handlers, and post status updates.
4. The orchestrator tracks cluster/job state and publishes status updates to `status.exchange`.
5. The Gateway consumes status updates from `status.queue`, updates stored job state, and streams SSE updates.

## Repository Layout

- `gateway/`: Spring Boot API gateway (Java 25, Spring Boot 4.0.2)
- `orchestrator/`: Erlang/OTP orchestrator + HTTP API + routing + RAFT-like FSM
- `workers/java-worker/`: Java worker (Spring Boot)
- `workers/python-worker/`: Python worker (`worker.py`)
- `docs/`: architecture notes + OpenAPI draft (`docs/api-spec.yaml`)
- `documentation/`: project report source and generated PDF
- `deploy/`: VM packaging and deployment scripts
- `monitoring/`: Prometheus scrape config (VM-oriented)
- `config/`: RabbitMQ and Nginx configs

## Prerequisites

For component-based local development:
- Java 25
- Maven 3.9+
- Erlang/OTP + `rebar3`
- Python 3.11+
- RabbitMQ 3.13+
- Redis 7+

For containerized workflows:
- Docker + Docker Compose

## Quick Start (Component-Based, Recommended)

This path matches the current checked-in service folders and configs.

### 1. Start RabbitMQ and Redis

```bash
docker run -d --name dq-rabbitmq \
  -p 5672:5672 -p 15672:15672 \
  rabbitmq:3.13-management-alpine

docker run -d --name dq-redis \
  -p 6379:6379 \
  redis:7.2-alpine
```

### 2. Start the orchestrator

```bash
cd orchestrator
rebar3 get-deps
rebar3 compile
rebar3 shell
```

Default orchestrator API: `http://localhost:8081`

### 3. Start the gateway

In a new terminal:

```bash
cd gateway
ERLANG_NODES=orchestrator@localhost \
ERLANG_REST_PORT=8081 \
RABBITMQ_ADDRESSES=localhost:5672 \
REDIS_HOST=localhost \
SERVER_PORT=8082 \
./mvnw spring-boot:run
```

Gateway base URL: `http://localhost:8082/api`

### 4. Start workers

Python worker (new terminal):

```bash
cd workers/python-worker
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

RABBITMQ_HOST=localhost \
RABBITMQ_PORT=5672 \
RABBITMQ_USERNAME=admin \
RABBITMQ_PASSWORD=admin \
ORCHESTRATOR_URL=http://localhost:8081 \
STATUS_UPDATE_URL=http://localhost:8081/api/jobs/status \
python worker.py
```

Java worker (new terminal):

```bash
cd workers/java-worker
RABBITMQ_ADDRESSES=localhost:5672 \
RABBITMQ_USERNAME=admin \
RABBITMQ_PASSWORD=admin \
STATUS_UPDATE_URL=http://localhost:8081/api/jobs/status \
./mvnw spring-boot:run
```

## API Usage

Gateway base path: `/api`

### Submit a job

```bash
curl -X POST http://localhost:8082/api/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "type": "calculate",
    "jobPriority": "HIGH",
    "payload": {
      "operation": "sum",
      "numbers": [1, 2, 3, 4, 5]
    }
  }'
```

### Get a job

```bash
curl http://localhost:8082/api/jobs/<job-id>
```

### List jobs

```bash
curl http://localhost:8082/api/jobs
```

### Stream SSE updates

```bash
curl http://localhost:8082/api/jobs/stream
```

### Gateway docs and metrics

- Swagger UI: `http://localhost:8082/api/swagger-ui.html`
- OpenAPI JSON: `http://localhost:8082/api/v3/api-docs`
- Health: `http://localhost:8082/api/actuator/health`
- Prometheus: `http://localhost:8082/api/actuator/prometheus`

## Orchestrator API

- `GET /api/health`
- `GET /api/cluster/status`
- `POST /api/jobs/register`
- `PUT /api/jobs/:id/status`
- `POST /api/jobs/status`
- `POST /api/jobs/:id/cancel`
- `GET /api/jobs`
- `GET /api/raft/status`
- `GET /api/metrics`
- `POST /api/workers/heartbeat`

Base URL (local): `http://localhost:8081`

## Build Commands

Gateway:

```bash
cd gateway
./mvnw clean package
```

Java worker:

```bash
cd workers/java-worker
./mvnw clean package
```

Orchestrator:

```bash
cd orchestrator
rebar3 compile
rebar3 release
```

## Deployment Material in This Repo

- VM packaging/build flow: `deploy/scripts/build.sh`
- VM deploy scripts: `deploy/scripts/deploy-vm1.sh`, `deploy/scripts/deploy-vm2.sh`
- Deployment checklist: `DEPLOYMENT.md`

## Current Inconsistencies to Be Aware Of

The repository contains some mixed-generation assets; if you use them as-is, expect manual fixes:

- `docker-compose.yml` points API gateway build context to `./client-api`, but this repo contains `gateway/`.
- `docker-compose.yml` mounts `./config/prometheus/...` and `./config/grafana/...`, while tracked monitoring config is under `monitoring/prometheus.yml`.
- Some scripts/docs still use `/api/v1/...` routes, while the current gateway controller maps `/api/jobs...`.
- VM docs/scripts reference both `10.2.1.3/10.2.1.4` and `10.2.1.11/10.2.1.12` topologies.

## Service-Specific Docs

- `gateway/README.md`
- `orchestrator/README.md`
- `workers/java-worker/README.md`
- `workers/python-worker/README.md`
- `docs/architecture.md`
- `docs/api-spec.yaml`

## License

MIT License. See `LICENSE`.
