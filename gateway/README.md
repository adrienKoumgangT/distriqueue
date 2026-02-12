# Gateway

Spring Boot gateway for DistriQueue. 
It exposes REST endpoints for job submission and management, persists job state to H2, publishes jobs to RabbitMQ,
integrates with Erlang orchestrators, and streams job updates via Server-Sent Events (SSE).

## Features
- Job submission (single and batch) with validation and metadata.
- Job lifecycle management: query, cancel, retry, and statistics.
- RabbitMQ routing by priority.
- H2 persistence with scheduled cleanup for old completed jobs.
- SSE stream for real-time job status updates.
- OpenAPI/Swagger UI and Prometheus metrics.

## Tech Stack
- Java 21, Spring Boot 4
- Spring Web, WebFlux, Validation, Data JPA
- RabbitMQ (AMQP), Redis
- H2 database
- Springdoc OpenAPI
- Micrometer Prometheus

## Requirements
- Java 21
- RabbitMQ instance
- Redis instance
- Erlang orchestrator nodes

## Configuration
Configuration lives in `src/main/resources/application.yaml` and can be overridden via environment variables.

Key environment variables:
- `SERVER_PORT` (default: 8080)
- `RABBITMQ_HOST` (default: rabbitmq1)
- `RABBITMQ_PORT` (default: 5672)
- `RABBITMQ_USERNAME` (default: admin)
- `RABBITMQ_PASSWORD` (default: admin)
- `REDIS_HOST` (default: localhost)
- `REDIS_PORT` (default: 6379)
- `ERLANG_NODES` (default: orchestrator1@distriqueue,orchestrator2@distriqueue)
- `ERLANG_REST_PORT` (default: 8081)
- `ERLANG_COOKIE` (default: distriqueue-cookie)
- `JOB_DEFAULT_TIMEOUT` (default: 300)
- `JOB_DEFAULT_RETRIES` (default: 3)
- `JOB_MAX_BATCH_SIZE` (default: 1000)
- `JOB_RETENTION_DAYS` (default: 30)
- `JOB_CLEANUP_ENABLED` (default: true)
- `WORKER_HEALTH_CHECK_INTERVAL` (default: 30000)
- `WORKER_HEALTH_TIMEOUT` (default: 120000)

RabbitMQ queue/exchange overrides:
- `RABBITMQ_EXCHANGE_JOBS` (default: jobs.exchange)
- `RABBITMQ_EXCHANGE_STATUS` (default: status.exchange)
- `RABBITMQ_QUEUE_JOB_HIGH` (default: job.high)
- `RABBITMQ_QUEUE_JOB_MEDIUM` (default: job.medium)
- `RABBITMQ_QUEUE_JOB_LOW` (default: job.low)
- `RABBITMQ_QUEUE_STATUS` (default: status.queue)
- `RABBITMQ_QUEUE_DEAD_LETTER` (default: job.dead-letter)

## Running Locally
1) Start RabbitMQ and Redis.
2) Run the app:

```bash
./mvnw spring-boot:run
```

The API is served under `/api`.

## API Endpoints
Base path: `/api`

- `POST /jobs` Submit a job
- `GET /jobs/{id}` Get job by ID
- `GET /jobs` Filter and paginate jobs
- `POST /jobs/batch` Submit a batch of jobs
- `POST /jobs/{id}/cancel` Cancel an active job
- `POST /jobs/{id}/retry` Retry a failed job
- `GET /jobs/statistics` Job statistics
- `GET /jobs/stream` SSE stream for job updates

### Example: Submit Job
```bash
curl -X POST http://localhost:8080/api/jobs \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "calculate",
    "jobPriority": "HIGH",
    "payload": {"numbers": [1, 2, 3, 4, 5]},
    "maxRetries": 3,
    "executionTimeout": 300
  }'
```

### Example: Stream Updates
```bash
curl http://localhost:8080/api/jobs/stream
```

## OpenAPI / Swagger
- `GET /api/swagger-ui.html`
- `GET /api/api-docs`

## Observability
- `GET /api/actuator/health`
- `GET /api/actuator/metrics`
- `GET /api/actuator/prometheus`

## Data and Logs
- H2 file DB: `./data/distriqueue`
- Logs: `./logs/gateway.log`

## Tests
```bash
./mvnw test
```
