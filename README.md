# DistriQueue

DistriQueue is a distributed job processing platform with an API gateway, an Erlang/OTP orchestrator cluster, and multiple worker implementations.
It routes jobs through RabbitMQ, tracks state, and exposes metrics for monitoring.

## What is included
- Gateway: Spring Boot API for job submission, status, and SSE updates.
- Orchestrator: Erlang/OTP cluster for scheduling, leader election, and routing.
- Workers: Java and Python workers that consume RabbitMQ queues.
- Monitoring: Prometheus and Grafana configs for visibility.

## Architecture (high level)
1) Clients submit jobs to the Gateway API.
2) The Gateway persists job state and publishes to RabbitMQ queues by priority.
3) Orchestrator nodes coordinate state and routing across the cluster.
4) Workers consume jobs and post status updates back to the Gateway.

## Quickstart (Docker Compose)
Build and run the full stack:

```bash
docker-compose build
docker-compose up -d
```

Check service logs:

```bash
docker-compose logs -f orchestrator1
docker-compose logs -f api-gateway
docker-compose logs -f python-worker1
```

Submit a test job:

```bash
curl -X POST http://localhost:8080/api/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "type": "calculate",
    "priority": "HIGH",
    "payload": {"numbers": [1, 2, 3, 4, 5]}
  }'
```

Stream job updates:

```bash
curl http://localhost:8080/api/jobs/stream
```

## Services and ports
- API Gateway: `http://localhost:8080`
- Orchestrator API: `http://localhost:8081`
- RabbitMQ management: `http://localhost:15672` (user/pass: `admin`/`admin`)
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`

## Repository layout
- `gateway/` Spring Boot API gateway
- `orchestrator/` Erlang/OTP orchestrator cluster node
- `workers/java-worker/` Java worker service
- `workers/python-worker/` Python worker service
- `monitoring/` Prometheus config
- `docs/` Architecture and API docs (see `docs/architecture.md`, `docs/api-spec.yaml`)

## Local development (without Docker)
Each service has its own README with detailed setup:
- `gateway/README.md`
- `orchestrator/README.md`
- `workers/java-worker/README.md`
- `workers/python-worker/README.md`

## Useful endpoints
Gateway (base path: `/api`):
- `POST /jobs` submit a job
- `GET /jobs/{id}` fetch job status
- `GET /jobs` list jobs
- `POST /jobs/{id}/cancel` cancel a job
- `POST /jobs/{id}/retry` retry a job
- `GET /jobs/statistics` job stats
- `GET /jobs/stream` SSE job updates

Orchestrator:
- `GET /api/health`
- `GET /api/cluster/status`
- `GET /api/metrics` (JSON)

## Build script
The `build-run.sh` script shows a full end-to-end flow for building, running, and exercising the API.
