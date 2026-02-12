#!/bin/bash
# Remote deployment script

set -e

VM1_IP="10.2.1.3"
VM2_IP="10.2.1.4"
SSH_USER="root"

echo "========================================="
echo "Deploying DistriQueue to VMs"
echo "========================================="

# Copy deployment package to VM1
echo "Copying to VM1 (${VM1_IP})..."
scp distriqueue-vm-deployment.tar.gz ${SSH_USER}@${VM1_IP}:/tmp/

# Copy deployment package to VM2
echo "Copying to VM2 (${VM2_IP})..."
scp distriqueue-vm-deployment.tar.gz ${SSH_USER}@${VM2_IP}:/tmp/

# Deploy on VM1
echo "Deploying on VM1..."
ssh ${SSH_USER}@${VM1_IP} << 'EOF'
    cd /tmp
    tar -xzf distriqueue-vm-deployment.tar.gz
    cd deploy
    chmod +x scripts/deploy-vm1.sh
    sudo ./scripts/deploy-vm1.sh
EOF

# Deploy on VM2
echo "Deploying on VM2..."
ssh ${SSH_USER}@${VM2_IP} << 'EOF'
    cd /tmp
    tar -xzf distriqueue-vm-deployment.tar.gz
    cd deploy
    chmod +x scripts/deploy-vm2.sh
    sudo ./scripts/deploy-vm2.sh
EOF

echo "========================================="
echo "✓ Remote deployment completed!"
echo "========================================="
