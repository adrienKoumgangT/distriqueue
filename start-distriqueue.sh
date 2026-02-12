#!/bin/bash

echo "========================================="
echo "Starting DistriQueue with H2 Database"
echo "========================================="

# Create directories
mkdir -p ./data/h2
mkdir -p ./logs
mkdir -p ./config/rabbitmq
mkdir -p ./config/nginx
mkdir -p ./config/prometheus
mkdir -p ./config/grafana/{dashboards,datasources}

# Set permissions
chmod -R 777 ./data/h2
chmod -R 777 ./logs

# Start services
docker-compose up -d

echo "========================================="
echo "DistriQueue started successfully!"
echo "========================================="
echo "API Gateway:      http://localhost:8080"
echo "API Gateway (LB): http://localhost"
echo "H2 Console:       http://localhost:8082"
echo "RabbitMQ UI:      http://localhost:15672 (admin/admin)"
echo "Prometheus:       http://localhost:9090"
echo "Grafana:          http://localhost:3000 (admin/admin)"
echo "Redis Commander:  http://localhost:8089 (admin/admin)"
echo "Portainer:        http://localhost:9000"
echo "========================================="
echo "H2 Database:"
echo "  JDBC URL: jdbc:h2:file:/app/data/distriqueue"
echo "  Username: sa"
echo "  Password: (empty)"
echo "========================================="

# Show logs
docker-compose logs -f
