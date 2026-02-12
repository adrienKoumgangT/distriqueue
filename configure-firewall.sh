#!/bin/bash

echo "Configuring firewall..."

# Allow SSH
sudo ufw allow 22/tcp

# RabbitMQ
sudo ufw allow 5672/tcp  # AMQP
sudo ufw allow 15672/tcp # Management
sudo ufw allow 15692/tcp # Prometheus

# Erlang/OTP
sudo ufw allow 4369/tcp  # EPMD
sudo ufw allow 9101/tcp  # Distribution port
sudo ufw allow 8081/tcp  # HTTP API

# API Gateway
sudo ufw allow 8080/tcp  # REST API
sudo ufw allow 8082/tcp  # H2 Console

# Workers
sudo ufw allow 8082-8085/tcp  # Java workers

# Monitoring
sudo ufw allow 9100/tcp  # Node Exporter
sudo ufw allow 9090/tcp  # Prometheus
sudo ufw allow 3000/tcp  # Grafana

# Redis
sudo ufw allow 6379/tcp

# Enable firewall
sudo ufw --force enable
sudo ufw status verbose
