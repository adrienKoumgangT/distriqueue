#!/bin/bash
# Deployment script for VM2 (10.2.1.4)

set -e

echo "========================================="
echo "Deploying DistriQueue on VM2 (10.2.1.4)"
echo "========================================="

# Load environment variables
source /opt/distriqueue/config/vm2.env

# Create directories
sudo mkdir -p /opt/distriqueue/{bin,config,data,logs,ssl}
sudo mkdir -p /opt/distriqueue/data/{h2,rabbitmq,redis}
sudo mkdir -p /opt/distriqueue/logs/{orchestrator,gateway,workers}

# Copy files
sudo cp -r packages/* /opt/distriqueue/bin/
sudo cp -r config/* /opt/distriqueue/config/
sudo cp -r ssl/* /opt/distriqueue/ssl/

# Set permissions
sudo chmod +x /opt/distriqueue/bin/*.sh
sudo chown -R $USER:$USER /opt/distriqueue

# ==========================================
# 1. Deploy RabbitMQ
# ==========================================
echo "Deploying RabbitMQ..."

# Create RabbitMQ configuration
cat > /opt/distriqueue/config/rabbitmq.conf << EOF
# RabbitMQ Configuration for VM1
listeners.tcp.default = 5672
management.tcp.port = 15672

cluster_name = distriqueue-cluster
cluster_formation.peer_discovery_backend = rabbit_peer_discovery_classic_config
cluster_formation.classic_config.nodes.1 = rabbit@distriqueue-vm1
cluster_formation.classic_config.nodes.2 = rabbit@distriqueue-vm2

default_user = admin
default_pass = SecurePass123!
default_user_tags.administrator = true

vm_memory_high_watermark.relative = 0.8
disk_free_limit.relative = 2.0

heartbeat = 60
EOF

# Start RabbitMQ
sudo systemctl stop rabbitmq-server || true
sudo cp /opt/distriqueue/config/rabbitmq.conf /etc/rabbitmq/rabbitmq.conf
sudo systemctl start rabbitmq-server
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl start_app

# Wait for RabbitMQ to start
sleep 10

# Configure RabbitMQ cluster
sudo rabbitmqctl set_cluster_name distriqueue-cluster

# Create vhosts and users
sudo rabbitmqctl add_vhost distriqueue || true
sudo rabbitmqctl add_vhost jobs || true
sudo rabbitmqctl add_user worker WorkerPass123! || true
sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
sudo rabbitmqctl set_permissions -p distriqueue admin ".*" ".*" ".*"
sudo rabbitmqctl set_permissions -p jobs admin ".*" ".*" ".*"
sudo rabbitmqctl set_permissions -p jobs worker "^job\\.(high|medium|low)$" "^amq\\.default$" "^job\\.(high|medium|low)$"

# Enable plugins
sudo rabbitmq-plugins enable rabbitmq_management
sudo rabbitmq-plugins enable rabbitmq_prometheus
sudo rabbitmq-plugins enable rabbitmq_federation
sudo rabbitmq-plugins enable rabbitmq_federation_management

# ==========================================
# 2. Deploy Redis
# ==========================================
echo "Deploying Redis..."

cat > /opt/distriqueue/config/redis.conf << EOF
port 6379
bind 0.0.0.0
requirepass RedisPass123!
appendonly yes
appendfilename "appendonly.aof"
save 900 1
save 300 10
save 60 10000
maxmemory 512mb
maxmemory-policy allkeys-lru
EOF

sudo cp /opt/distriqueue/config/redis.conf /etc/redis/redis.conf
sudo systemctl restart redis-server

# ==========================================
# 3. Deploy Erlang Orchestrator
# ==========================================
echo "Deploying Erlang Orchestrator..."

cd /opt/distriqueue
tar -xzf bin/distriqueue-orchestrator.tar.gz

# Create orchestrator configuration
cat > /opt/distriqueue/config/orchestrator.vm.args << EOF
-name ${ERLANG_NODE_NAME}
-setcookie ${ERLANG_COOKIE}
-heart
+K true
+A 64
+P 250000
+smp auto
EOF

cat > /opt/distriqueue/config/orchestrator.config << EOF
[
 {distriqueue, [
    {node_name, "${ERLANG_NODE_NAME}"},
    {cookie, "${ERLANG_COOKIE}"},
    {rabbitmq_host, "${HOST_IP}"},
    {rabbitmq_port, 5672},
    {rabbitmq_username, "admin"},
    {rabbitmq_password, "SecurePass123!"},
    {http_port, 8081},
    {metrics_port, 9100},
    {raft_peers, ["${ERLANG_RAFT_PEERS}"]}
 ]}
].
EOF

# Create systemd service for orchestrator
cat > /tmp/distriqueue-orchestrator.service << EOF
[Unit]
Description=DistriQueue Erlang Orchestrator
After=network.target rabbitmq-server.service redis-server.service
Requires=rabbitmq-server.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/distriqueue/rel/distriqueue
EnvironmentFile=/opt/distriqueue/config/vm2.env
ExecStart=/opt/distriqueue/rel/distriqueue/bin/distriqueue foreground
ExecStop=/opt/distriqueue/rel/distriqueue/bin/distriqueue stop
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/distriqueue-orchestrator.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable distriqueue-orchestrator
sudo systemctl start distriqueue-orchestrator

# ==========================================
# 4. Deploy API Gateway
# ==========================================
echo "Deploying API Gateway..."

# Create API Gateway configuration
cat > /opt/distriqueue/config/application-vm2.yml << EOF
server:
  port: ${API_GATEWAY_PORT}

spring:
  datasource:
    url: jdbc:h2:file:${H2_DB_PATH}/distriqueue;DB_CLOSE_DELAY=-1;MODE=PostgreSQL
    username: sa
    password:
  h2:
    console:
      enabled: true
      path: /h2-console
  rabbitmq:
    host: ${HOST_IP}
    port: 5672
    username: admin
    password: SecurePass123!
  redis:
    host: ${HOST_IP}
    port: 6379
    password: RedisPass123!

distriqueue:
  erlang:
    nodes: ${ERLANG_NODES}
    mode: http
    rest:
      port: 8081
EOF

# Create systemd service for API Gateway
cat > /tmp/distriqueue-api.service << EOF
[Unit]
Description=DistriQueue API Gateway
After=network.target rabbitmq-server.service redis-server.service distriqueue-orchestrator.service
Requires=distriqueue-orchestrator.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/distriqueue
EnvironmentFile=/opt/distriqueue/config/vm2.env
ExecStart=/usr/bin/java -jar /opt/distriqueue/bin/distriqueue-api-gateway.jar \
    --spring.config.location=/opt/distriqueue/config/application-vm2.yml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/distriqueue-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable distriqueue-api
sudo systemctl start distriqueue-api

# ==========================================
# 5. Deploy Workers
# ==========================================
echo "Deploying Workers..."

# Python Worker
echo "Deploying Python Worker..."
cat > /tmp/distriqueue-python-worker.service << EOF
[Unit]
Description=DistriQueue Python Worker
After=network.target rabbitmq-server.service
Requires=rabbitmq-server.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/distriqueue
EnvironmentFile=/opt/distriqueue/config/vm2.env
ExecStart=/usr/bin/python3 /opt/distriqueue/bin/worker.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/distriqueue-python-worker.service /etc/systemd/system/
sudo systemctl enable distriqueue-python-worker
sudo systemctl start distriqueue-python-worker

# Java Worker
echo "Deploying Java Worker..."
cat > /tmp/distriqueue-java-worker.service << EOF
[Unit]
Description=DistriQueue Java Worker
After=network.target rabbitmq-server.service
Requires=rabbitmq-server.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/distriqueue
EnvironmentFile=/opt/distriqueue/config/vm2.env
ExecStart=/usr/bin/java -jar /opt/distriqueue/bin/distriqueue-java-worker.jar
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/distriqueue-java-worker.service /etc/systemd/system/
sudo systemctl enable distriqueue-java-worker
sudo systemctl start distriqueue-java-worker

# ==========================================
# 6. Setup Monitoring
# ==========================================
echo "Setting up monitoring..."

# Prometheus Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xzf node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

cat > /tmp/node_exporter.service << EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/node_exporter.service /etc/systemd/system/
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

echo "========================================="
echo "✓ Deployment completed on VM1"
echo "========================================="
