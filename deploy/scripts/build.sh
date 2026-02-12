#!/bin/bash
# Build script for DistriQueue deployment

set -e

echo "========================================="
echo "Building DistriQueue for VM Deployment"
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check Java version
JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
echo -e "${YELLOW}Java version: $JAVA_VERSION${NC}"

# Check Maven version
MVN_VERSION=$(mvn --version | head -n1)
echo -e "${YELLOW}Maven version: $MVN_VERSION${NC}"

# Check Erlang version
ERL_VERSION=$(erl -version 2>&1)
echo -e "${YELLOW}Erlang version: $ERL_VERSION${NC}"

# Build orchestrator
echo -e "\n${GREEN}Building Erlang Orchestrator...${NC}"
cd orchestrator
rebar3 compile
rebar3 release
tar -czf distriqueue-orchestrator.tar.gz _build/default/rel/distriqueue/
mv distriqueue-orchestrator.tar.gz ../deploy/packages/
cd ..

# Build API Gateway
echo -e "\n${GREEN}Building Java API Gateway...${NC}"
cd gateway
mvn clean package -DskipTests -Pvm-deploy
cp target/gateway-*.jar ../deploy/packages/distriqueue-api-gateway.jar
cd ..

# Build Java Worker
echo -e "\n${GREEN}Building Java Worker...${NC}"
cd workers/java-worker
mvn clean package -DskipTests
cp target/java-worker-*.jar ../../deploy/packages/distriqueue-java-worker.jar
cd ../..

# Build Python Worker (package as tar)
echo -e "\n${GREEN}Packaging Python Worker...${NC}"
cd workers/python-worker
tar -czf distriqueue-python-worker.tar.gz \
    worker.py \
    requirements.txt \
    Dockerfile \
    ../deploy/scripts/python-worker.service
mv distriqueue-python-worker.tar.gz ../../deploy/packages/
cd ../..

# Create deployment package
echo -e "\n${GREEN}Creating master deployment package...${NC}"
cd deploy
tar -czf distriqueue-vm-deployment.tar.gz \
    packages/ \
    scripts/ \
    config/ \
    ssl/ \
    ../README.md \
    ../LICENSE

echo -e "\n${GREEN}✓ Build completed successfully!${NC}"
echo "Deployment package: deploy/distriqueue-vm-deployment.tar.gz"
