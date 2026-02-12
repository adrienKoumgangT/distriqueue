#!/bin/bash
# scripts/demo_scenarios.sh

echo "=== DistriQueue Demo Script ==="
echo "Starting all services..."
docker-compose up -d

echo -e "\nWaiting for services to start..."
sleep 30

echo -e "\n=== Scenario 1: Normal Operation ==="
echo "Submitting test jobs..."
python scripts/test_submit.py --single

echo -e "\n=== Scenario 2: Fault Tolerance ==="
echo "Stopping leader orchestrator..."
docker-compose stop orchestrator1
sleep 5

echo "Submitting more jobs during leader failure..."
python scripts/test_submit.py --single
sleep 10

echo "Restoring leader..."
docker-compose start orchestrator1
sleep 5

echo -e "\n=== Scenario 3: Worker Failure ==="
echo "Stopping a worker..."
docker-compose stop python-worker1
sleep 5

echo "Submitting jobs with worker down..."
python scripts/test_submit.py --load 20
sleep 10

echo "Restoring worker..."
docker-compose start python-worker1

echo -e "\n=== Scenario 4: Load Handling ==="
echo "Submitting 100 jobs..."
python scripts/test_submit.py --load 100

echo -e "\n=== Monitoring ==="
echo "RabbitMQ Management: http://localhost:15672 (admin/admin)"
echo "API Gateway: http://localhost:8080/api/v1/jobs"
echo "Prometheus: http://localhost:9090"
echo "Grafana: http://localhost:3000 (admin/admin)"

echo -e "\nPress Ctrl+C to stop all services..."
read -p "Press enter to stop demo..."

echo "Stopping all services..."
docker-compose down
