# python-worker

A Python worker service for a RabbitMQ-backed distributed job processing system.  
It consumes jobs from priority queues, executes them using built-in handlers, and reports status + heartbeats to an orchestrator/API.

## What it does

- Connects to **RabbitMQ** and consumes from these queues:
  - `job.high`
  - `job.medium`
  - `job.low`
  - (dead letter queue: `job.dead-letter`)
- Processes each job and sends status updates to an HTTP endpoint (e.g., an API gateway).
- Periodically sends worker heartbeats to an orchestrator service.
- Includes built-in job handlers for:
  - **Calculations** (sum/avg/min/max/sort/aggregate/statistics)
  - **Transformations** (uppercase/lowercase/reverse/filter/normalize)
  - **Validation** (email/phone/numeric/required/range/length/regex)

## Project structure

- `worker.py` — main worker implementation (entrypoint)
- `requirements.txt` — Python dependencies
- `Dockerfile` — container image for running the worker
- `main.py` — placeholder/sample script (not used by the worker)

## Requirements

- Python **3.11+** (if running locally)
- A reachable RabbitMQ broker
- HTTP endpoints for:
  - worker heartbeats (orchestrator)
  - job status updates (API)

## Configuration (environment variables)

The worker reads configuration from environment variables (defaults exist, but you’ll usually override them in real deployments):

| Variable | Description | Example |
|---|---|---|
| `RABBITMQ_HOST` | RabbitMQ hostname | `10.2.1.11` |
| `RABBITMQ_PORT` | RabbitMQ port | `5672` |
| `RABBITMQ_USERNAME` | RabbitMQ username | `<RABBITMQ_USERNAME>` |
| `RABBITMQ_PASSWORD` | RabbitMQ password | `<RABBITMQ_PASSWORD>` |
| `WORKER_ID` | Optional fixed worker id (otherwise auto-generated) | `python-worker-01` |
| `WORKER_TYPE` | Worker type label | `python` |
| `WORKER_CAPACITY` | Max concurrency value used by the worker | `10` |
| `ORCHESTRATOR_URL` | Base URL for orchestrator heartbeats | `http://10.2.1.11:8081` |
| `STATUS_UPDATE_URL` | URL for posting job status updates | `http://10.2.1.11:8080/api/jobs/status` |

## Run locally (Python)

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export RABBITMQ_HOST=localhost
export RABBITMQ_PORT=5672
export RABBITMQ_USERNAME=<RABBITMQ_USERNAME>
export RABBITMQ_PASSWORD=<RABBITMQ_PASSWORD>
export ORCHESTRATOR_URL=http://localhost:8081
export STATUS_UPDATE_URL=http://localhost:8080/api/v1/jobs/status
export WORKER_CAPACITY=10

python worker.py
```

This worker is deployed on **two virtual machines**:

- **VM1**: `10.2.1.11`
- **VM2**: `10.2.1.12`

Make sure both instances are configured consistently (same RabbitMQ and API endpoints, different optional `WORKER_ID` values if you want fixed identities).

Example environment for each VM:

### Build

```bash
docker build -t python-worker:local .
```
### Run

```bash
docker run --rm -it \
  -e RABBITMQ_HOST=host.docker.internal \
  -e RABBITMQ_PORT=5672 \
  -e RABBITMQ_USERNAME=<RABBITMQ_USERNAME> \
  -e RABBITMQ_PASSWORD=<RABBITMQ_PASSWORD> \
  -e ORCHESTRATOR_URL=http://host.docker.internal:8081 \
  -e STATUS_UPDATE_URL=http://host.docker.internal:8080/api/v1/jobs/status \
  -e WORKER_CAPACITY=10 \
  python-worker:local
```
> Note (macOS): `host.docker.internal` usually resolves to your host machine from inside Docker.

## Job format (expected)

Jobs are expected to be JSON messages. The worker uses at least:

- `id` — job identifier
- `type` — job type used for handler selection
- `payload` — handler-specific data

Example message:
```json
{
  "id": "job-123",
  "type": "calculate",
  "payload": {
    "operation": "sum",
    "numbers": [1, 2, 3, 4]
  }
}
```

### Supported job types (built-in)

**Calculation handler** supports types:
- `calculate`, `sum`, `average`, `min`, `max`, `sort`, `aggregate`

Common `payload`:
- `operation`: `sum | average | min | max | sort | aggregate | statistics`
- `numbers`: list of numbers (if omitted, the worker may generate random numbers)
- `count`: how many random numbers to generate (if `numbers` not provided)

**Transformation handler** supports types:
- `transform`, `uppercase`, `lowercase`, `reverse`, `filter`, `normalize`

Common `payload`:
- `operation`: `uppercase | lowercase | reverse | filter | normalize`
- `data`: object/dict to transform

**Validation handler** supports types:
- `validate`, `email`, `phone`, `numeric`, `required`, `range`, `length`, `regex`

Common `payload`:
- `type`: `email | phone | numeric | required | range | length | regex`
- `value`: value to validate
- additional fields depending on type (e.g., `min/max`, `pattern`, etc.)

## Status updates & heartbeats

- **Job status updates** are posted to `STATUS_UPDATE_URL` with fields like:
  - `jobId`, `status` (`running` / `completed` / `failed`), `workerId`, `timestamp`
  - optionally `result`, `errorMessage`, `progress`

- **Heartbeats** are posted to:
  - `${ORCHESTRATOR_URL}/api/workers/heartbeat`
  - includes worker load/capacity and processing counters

## Observability

The worker logs:
- connection attempts and failures
- per-job processing outcomes
- periodic metrics (load, processed count, success rate, average job time)

## Notes / gotchas

- This worker declares queues/exchange on startup (direct exchange: `jobs.exchange`).
- Dead-letter routing is configured to `job.dead-letter`.
- Ensure your RabbitMQ user has permissions to declare exchanges/queues and consume messages.

