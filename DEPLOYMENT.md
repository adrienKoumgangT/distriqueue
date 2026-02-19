# DistriQueue VM Deployment - Quick Start

## Prerequisites

1. Two Ubuntu 24.04 VMs with IPs: 10.2.1.3, 10.2.1.4
2. Java 25.0.1-open installed
3. Python 3.11+ and Python3 env installed
4. Erlang/OTP 28 installed
5. Maven 3.9.11 installed
6. Git installed


## Deployment Steps


### Download DistriQueue

```bash
cd /opt

rm -rf distriqueue/

git clone https://github.com/adrienKoumgangT/distriqueue.git

cd distriqueue
```

### Orchestrator (Erlang Nodes)

```bash
cd /opt/distriqueue/orchestrator/

# for vm2 (10.2.1.12)
# edit config/sys.config and config/vm.args
# replace 10.2.1.11 with 10.2.1.12
# nano config/sys.config # replace orchestrator@Adrien0.local with orchestrator@Adrien1.local
# nano config/vm.args #  replace orchestrator@Adrien0 with orchestrator@Adrien1 and vice versa

chmod +x build-orchestrator.sh

./build-orchestrator.sh

/opt/distriqueue/orchestrator/_build/default/rel/distriqueue/bin/distriqueue daemon
```

**To check if it is up and running:**
```bash
curl -s http://localhost:8081/api/health

curl -s http://localhost:8081/api/raft/status
```

**To stop it and kill all the Erlang processes:**
```bash
cd /opt/distriqueue/orchestrator/

_build/default/rel/distriqueue/bin/distriqueue stop

pkill -9 beam.smp

pkill -9 heart

# If we want to clean the build:
# rm -rf _build/
```

### Python Workers

```bash
cd /opt/distriqueue/workers/python-worker/

python3 -m venv worker-env

source worker-env/bin/activate

pip install -r requirements.txt

export ORCHESTRATOR_URL="http://10.2.1.11:8081"
# for vm2 (10.2.1.12): export ORCHESTRATOR_URL="http://10.2.1.12:8081"

export STATUS_UPDATE_URL="http://10.2.1.11:8081/api/jobs/status"
# for vm2(10.2.1.12): export STATUS_UPDATE_URL="http://10.2.1.11:8082/api/jobs/status"

python worker.py
```

To launch this worker in the background:
```bash
nohup python3 worker.py > worker.log 2>&1 &

# To see the live logs anytime:
tail -f worker.log


# To kill the worker:
kill -9 $(pgrep -f "python3 worker.py")
# or
pkill -f "python3 worker.py"
```


### Java Workers

```bash
cd /opt/distriqueue/workers/java-worker/

mvn clean package -DskipTests

export RABBITMQ_ADDRESSES="10.2.1.12:5672"
# for vm2 (10.2.1.12): export RABBITMQ_ADDRESSES="10.2.1.12:5672"

export STATUS_UPDATE_URL="http://10.2.1.11:8081/api/jobs/status"
# for vm2 (10.2.1.12): export STATUS_UPDATE_URL="http://10.2.1.12:8082/api/jobs/status"

java -jar target/java-worker-0.0.1-SNAPSHOT.jar
```

To launch this worker in the background:
```bash
nohup java -jar target/java-worker-0.0.1-SNAPSHOT.jar > worker.log 2>&1 &

# To see the live logs anytime:
tail -f worker.log

kill -9 $(pgrep -f "java -jar target/java-worker-0.0.1-SNAPSHOT.jar")
# or
pkill -f "java -jar target/java-worker-0.0.1-SNAPSHOT.jar"
```

### APi Gateway
```bash
cd /opt/distriqueue/gateway/

mvn clean package -DskipTests

java -jar target/gateway-0.0.1-SNAPSHOT.jar
```

**To test the system**:
Call the API Gateway with a POST request to POST http://10.2.1.11:8080/api/jobs with the following body:
```json
{
  "type": "calculate",
  "jobPriority": "HIGH",
  "payload": {
    "operation": "sum",
    "numbers": [1000, 2000, 3000]
  },
  "maxRetries": 3,
  "executionTimeout": 300
}
```

## Access Points

- API Gateway: http://10.2.1.3:8080, http://10.2.1.4:8080
- H2 Console: http://10.2.1.3:8082/h2-console (JDBC: jdbc:h2:file:/opt/distriqueue/data/h2/distriqueue)
- RabbitMQ Management: http://10.2.1.3:15672 (admin/admin!)
- Erlang Orchestrator API: http://10.2.1.3:8081/api/cluster/status

## Monitoring

- Node Exporter: http://10.2.1.3:9100/metrics
- RabbitMQ Metrics: http://10.2.1.3:15692/metrics
