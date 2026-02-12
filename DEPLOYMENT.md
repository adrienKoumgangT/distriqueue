# DistriQueue VM Deployment - Quick Start

## Prerequisites

1. Two Ubuntu 24.04 VMs with IPs: 10.2.1.3, 10.2.1.4
2. Java 25.0.1-open installed
3. Erlang/OTP 28 installed
4. Maven 3.9.11 installed
5. Git installed

## Steps

### Step 1: Clone and Build

```bash
git clone https://github.com/adrienKoumgangT/distriqueue.git
cd distriqueue
chmod +x deploy/scripts/build.sh
./deploy/scripts/build.sh
```

### Step 2: Configure VMs

```bash
git clone https://github.com/adrienKoumgangT/distriqueue.git
cd distriqueue
chmod +x deploy/scripts/build.sh
./deploy/scripts/build.sh
```

### Step 3: Deploy to VM1

```bash
# From your local machine:
scp deploy/distriqueue-vm-deployment.tar.gz ubuntu@10.2.1.3:/tmp/
ssh ubuntu@10.2.1.3
cd /tmp
tar -xzf distriqueue-vm-deployment.tar.gz
cd deploy
sudo ./scripts/deploy-vm1.sh
```

### Step 4: Deploy to VM2

```bash
# From your local machine:
scp deploy/distriqueue-vm-deployment.tar.gz ubuntu@10.2.1.4:/tmp/
ssh ubuntu@10.2.1.4
cd /tmp
tar -xzf distriqueue-vm-deployment.tar.gz
cd deploy
sudo ./scripts/deploy-vm2.sh
```

### Step 5: Verify Deployment

```bash
./deploy/scripts/verify-deployment.sh
```

## Access Points

- API Gateway: http://10.2.1.3:8080, http://10.2.1.4:8080
- H2 Console: http://10.2.1.3:8082/h2-console (JDBC: jdbc:h2:file:/opt/distriqueue/data/h2/distriqueue)
- RabbitMQ Management: http://10.2.1.3:15672 (admin/SecurePass123!)
- Erlang Orchestrator API: http://10.2.1.3:8081/api/cluster/status

## Monitoring

- Node Exporter: http://10.2.1.3:9100/metrics
- RabbitMQ Metrics: http://10.2.1.3:15692/metrics
