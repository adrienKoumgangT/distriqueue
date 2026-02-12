#!/bin/bash
# Verify deployment

echo "========================================="
echo "Verifying DistriQueue Deployment"
echo "========================================="

VM1="10.2.1.3"
VM2="10.2.1.4"

check_service() {
    local host=$1
    local port=$2
    local name=$3

    nc -zv $host $port 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ $name on $host:$port is UP"
    else
        echo "✗ $name on $host:$port is DOWN"
    fi
}

# Check services on VM1
echo "Checking VM1 (10.2.1.3)..."
check_service $VM1 5672 "RabbitMQ AMQP"
check_service $VM1 15672 "RabbitMQ Management"
check_service $VM1 6379 "Redis"
check_service $VM1 8081 "Erlang Orchestrator"
check_service $VM1 8080 "API Gateway"
check_service $VM1 9100 "Node Exporter"

# Check services on VM2
echo "Checking VM2 (10.2.1.4)..."
check_service $VM2 5672 "RabbitMQ AMQP"
check_service $VM2 15672 "RabbitMQ Management"
check_service $VM2 6379 "Redis"
check_service $VM2 8081 "Erlang Orchestrator"
check_service $VM2 8080 "API Gateway"
check_service $VM2 9100 "Node Exporter"

# Test API endpoints
echo "Testing API endpoints..."
curl -s http://$VM1:8080/actuator/health | grep -q '"status":"UP"'
if [ $? -eq 0 ]; then
    echo "✓ API Gateway health check PASSED"
else
    echo "✗ API Gateway health check FAILED"
fi

# Test Erlang cluster
echo "Testing Erlang cluster..."
curl -s http://$VM1:8081/api/cluster/status | grep -q "orchestrator"
if [ $? -eq 0 ]; then
    echo "✓ Erlang cluster status PASSED"
else
    echo "✗ Erlang cluster status FAILED"
fi

echo "========================================="
