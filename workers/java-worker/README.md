# DistriQueue Java Worker

Java worker service for the DistriQueue platform.
It consumes jobs from RabbitMQ, processes them asynchronously, and posts status updates back to the API gateway.
It also exposes health and Prometheus metrics via Spring Boot Actuator.

## Features
- RabbitMQ consumers with priority queues and retry handling.
- Job handlers for calculation, transformation, and validation tasks.
- Status updates to the orchestrator/API gateway.
- Worker health checks and heartbeat reporting.
- Micrometer + Prometheus metrics.

## Architecture
- `JobConsumer` listens on the configured queues and dispatches to a matching `JobHandler`.
- Handlers run asynchronously and return a `JobResult`.
- Status updates are posted to `distriqueue.worker.status.update-url`.
- Metrics are exported on `/worker/actuator/prometheus`.

## Job Types
Supported job types are defined in `Job.Types`:
- `calculate`, `sort`, `aggregate` (calculation handler)
- `transform`, `filter` (transformation handler)
- `validate` (validation handler)

Payload formats are flexible JSON maps. See handler implementations for supported operations.

## Configuration
Key settings are in `src/main/resources/application.yml`.

### Environment variables
- `RABBITMQ_HOST` (default: `rabbitmq1`)
- `RABBITMQ_PORT` (default: `5672`)
- `RABBITMQ_USERNAME` (default: `admin`)
- `RABBITMQ_PASSWORD` (default: `admin`)
- `WORKER_ID` (default: `java-worker-${random.uuid}`)
- `WORKER_TYPE` (default: `java`)
- `WORKER_CAPACITY` (default: `10`)
- `STATUS_UPDATE_URL` (default: `http://api-gateway:8080/api/jobs/status`)
- `SERVER_PORT` (default: `8082`)
- `DISTRIQUEUE_ERLANG_NODES` (comma-separated, maps to `distriqueue.erlang.nodes`)

### Queues
The worker consumes from:
- `job.high`
- `job.medium`
- `job.low`

Queues are bound to the direct exchange `jobs.exchange` with the same routing keys.
A dead-letter queue `job.dead-letter` is also declared.

## Running locally
Requirements:
- Java 21
- RabbitMQ

```bash
./mvnw spring-boot:run
```

## Build
```bash
./mvnw clean package
```

## Docker
The Dockerfile expects a built JAR at `target/java-worker-1.0.0.jar`.

```bash
./mvnw clean package
docker build -f docker/Dockerfile -t distriqueue/java-worker:local .
```

## Endpoints
- Health: `http://localhost:8082/api/worker/actuator/health`
- Metrics (Prometheus): `http://localhost:8082/api/worker/actuator/prometheus`
- Info/Metrics: `http://localhost:8082/api/worker/actuator/metrics`

## Status updates
Status updates are sent as JSON to the configured `STATUS_UPDATE_URL`.

## Development notes
- Retry behavior is configured both at the RabbitMQ listener and in handler logic.
- Job processing concurrency is controlled by `distriqueue.worker.job.concurrency`.
