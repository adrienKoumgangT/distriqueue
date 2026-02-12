# Build all services
docker-compose build

# Start the cluster
docker-compose up -d

# Check logs
docker-compose logs -f orchestrator1
docker-compose logs -f gateway
docker-compose logs -f python-worker1

# Submit test jobs
curl -X POST http://localhost:8080/api/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "type": "calculate",
    "priority": "high",
    "payload": {"numbers": [1, 2, 3, 4, 5]}
  }'

# Submit a calculation job
curl -X POST http://localhost:8080/api/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "type": "calculate",
    "priority": "HIGH",
    "payload": {
      "operation": "sum",
      "numbers": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    }
  }'

# Submit a transformation job
curl -X POST http://localhost:8080/api/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "type": "transform",
    "priority": "MEDIUM",
    "payload": {
      "operation": "uppercase",
      "data": {
        "name": "john",
        "city": "new york",
        "country": "usa"
      }
    }
  }'

# Submit a validation job
curl -X POST http://localhost:8080/api/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "type": "validate",
    "priority": "LOW",
    "payload": {
      "type": "email",
      "value": "test@example.com"
    }
  }'

# Check job status
curl http://localhost:8080/api/jobs/{job_id}

# Get all jobs
curl http://localhost:8080/api/jobs

# Stream job updates (SSE)
curl http://localhost:8080/api/jobs/stream
