# DistriQueue Architecture

DistriQueue is a distributed job processing platform with a Spring Boot API gateway, an Erlang/OTP orchestrator cluster, and multiple worker implementations.
RabbitMQ provides priority queues, while Redis/H2 handle persistence and caching.
Prometheus and Grafana support observability.

## Goals
- Accept jobs with priority and metadata through a stable REST API.
- Route jobs to workers with cluster-level coordination and failover.
- Track job state and expose lifecycle events in real time.
- Provide metrics for throughput, latency, and worker health.

## Core components

### API gateway (Spring Boot)
- Entry point for clients and admin tools.
- Validates job requests and persists job state to H2.
- Publishes jobs to RabbitMQ with routing by priority.
- Streams job status updates over SSE.
- Exposes OpenAPI endpoints and Prometheus metrics.

### Orchestrator cluster (Erlang/OTP)
- Manages distributed state and leader election.
- Tracks job registry and worker health.
- Coordinates routing decisions and cluster status.
- Exposes a lightweight HTTP API for cluster health and metrics.

### Workers (Java, Python)
- Consume jobs from priority queues.
- Execute handlers by job type and report status updates.
- Publish heartbeats and load/capacity info.

### Messaging and storage
- RabbitMQ provides queues and exchanges for job dispatch and status routing.
- H2 stores gateway job state and enables querying/history.
- Redis is used by the gateway for caching and transient state.

### Observability
- Prometheus scrapes gateway, orchestrator, and worker metrics.
- Grafana dashboards visualize cluster health and job throughput.

## High-level flow
1) Client submits a job to the Gateway API.
2) Gateway validates, persists metadata, and publishes the job to RabbitMQ.
3) Orchestrator nodes coordinate routing and update cluster state.
4) Workers consume jobs and execute handlers.
5) Workers post status updates back to the Gateway.
6) Gateway updates job state and emits SSE events.

## Job lifecycle
- `pending` -> `running` -> `completed`
- `pending` -> `running` -> `failed` (optionally retry)
- `pending` -> `cancelled`

## Deployment topology (Docker Compose)
- RabbitMQ cluster: `rabbitmq1`, `rabbitmq2`
- Orchestrators: `orchestrator1`, `orchestrator2`
- API gateway: `api-gateway`
- Workers: `python-worker1`, `java-worker`
- Monitoring: `prometheus`, `grafana`

## Configuration
- Gateway config: `gateway/src/main/resources/application.yaml`
- Orchestrator config: `orchestrator/config/sys.config`, `orchestrator/config/vm.args`
- Worker configs: `workers/java-worker/src/main/resources/application.yml`, `workers/python-worker/requirements.txt` plus environment variables

## Failure handling
- Orchestrator leader election ensures single-writer coordination.
- Jobs can be retried by the Gateway on failure.
- Workers send heartbeats; stale workers are flagged by the orchestrator.

## Security considerations
- RabbitMQ credentials are configured via environment variables.
- Network-level security (TLS, auth) is expected to be handled by deployment infrastructure.

## Related docs
- API spec: `docs/api-spec.yaml`
- Gateway: `gateway/README.md`
- Orchestrator: `orchestrator/README.md`
- Java worker: `workers/java-worker/README.md`
- Python worker: `workers/python-worker/README.md`
