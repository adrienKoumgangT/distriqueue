#!/bin/bash

echo "Configuring /etc/hosts..."

cat >> /etc/hosts << EOF

# DistriQueue Cluster
10.2.1.3    distriqueue-vm1
10.2.1.4    distriqueue-vm2

# RabbitMQ Cluster
10.2.1.3    rabbitmq-vm1
10.2.1.4    rabbitmq-vm2

# Erlang Nodes
10.2.1.3    orchestrator1.distriqueue.local
10.2.1.4    orchestrator2.distriqueue.local
EOF
