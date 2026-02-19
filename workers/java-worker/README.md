# DistriQueue Java Worker

`java-worker` is a Spring Boot worker service for DistriQueue.

It:
- consumes jobs from RabbitMQ priority queues (`job.high`, `job.medium`, `job.low`)
- dispatches jobs to typed handlers (`calculate`, `transform`, `validate`, etc.)
- sends job status updates to the orchestrator/API
- sends heartbeat events to Erlang orchestrator nodes
- exposes Actuator + Prometheus metrics

## Runtime Architecture
- `JobConsumer` listens on queues from `distriqueue.worker.queues`.
- Each job is routed to a `JobHandler` implementation:
  - `CalculationJobHandler`: `calculate`, `sort`, `aggregate`
  - `TransformationJobHandler`: `transform`, `filter`
  - `ValidationJobHandler`: `validate`
- Processing runs asynchronously with `jobProcessingExecutor`.
- Status updates are posted by `StatusUpdateService`.
- Heartbeats are sent by `HealthService` to each configured Erlang node.

## Requirements
- Java `25` (from `pom.xml`)
- Maven (or use `./mvnw`)
- RabbitMQ reachable from worker hosts

## Configuration
Main config file: `src/main/resources/application.yml`

Important environment variables:
- `RABBITMQ_ADDRESSES` (default: `10.2.1.11:5672,10.2.1.12:5672`)
- `RABBITMQ_USERNAME` (default: `admin`)
- `RABBITMQ_PASSWORD` (default: `admin`)
- `WORKER_ID` (default: `java-worker-${random.uuid}`)
- `WORKER_TYPE` (default: `java`)
- `WORKER_CAPACITY` (default: `15`)
- `QUEUES` (default: `job.high,job.medium,job.low`)
- `STATUS_UPDATE_URL` (default: `http://10.2.1.11:8081/api/jobs/status`)

Also configured by default:
- Erlang nodes: `orchestrator@10.2.1.11,orchestrator@10.2.1.12`
- listener concurrency: `3..10`
- job concurrency: `5`

## Local Run
```bash
./mvnw spring-boot:run
```

## Build
```bash
./mvnw clean package
```

Expected artifact:
- `target/java-worker-0.0.1-SNAPSHOT.jar`

## Deploy On 2 VMs (10.2.1.11 and 10.2.1.12)
Deploy one worker instance per VM with identical config (except `WORKER_ID`).

### 1. Copy artifact to both VMs
```bash
./mvnw clean package
scp target/java-worker-0.0.1-SNAPSHOT.jar user@10.2.1.11:/opt/distriqueue/java-worker/app.jar
scp target/java-worker-0.0.1-SNAPSHOT.jar user@10.2.1.12:/opt/distriqueue/java-worker/app.jar
```

### 2. Environment per VM
Use this on both VMs:
```bash
export RABBITMQ_ADDRESSES=10.2.1.11:5672,10.2.1.12:5672
export RABBITMQ_USERNAME=admin
export RABBITMQ_PASSWORD=admin
export STATUS_UPDATE_URL=http://10.2.1.11:8081/api/jobs/status
export QUEUES=job.high,job.medium,job.low
export WORKER_TYPE=java
```

Set a different worker ID on each VM:
- VM `10.2.1.11`: `WORKER_ID=java-worker-10-2-1-11`
- VM `10.2.1.12`: `WORKER_ID=java-worker-10-2-1-12`

### 3. Start worker
```bash
java -jar /opt/distriqueue/java-worker/app.jar
```

## Health and Metrics
Actuator endpoints (default port `8080` unless overridden, with `server.servlet.context-path: /api`):
- `/api/actuator/health`
- `/api/actuator/info`
- `/api/actuator/metrics`
- `/api/actuator/prometheus`

Example:
- `http://<worker-host>:8080/api/actuator/health`
- `http://<worker-host>:8080/api/actuator/prometheus`
