#!/bin/bash
# system-tuning.sh

echo "Tuning system parameters..."

# Increase system limits
cat >> /etc/security/limits.conf << EOF
*               soft    nofile          65536
*               hard    nofile          65536
*               soft    nproc           unlimited
*               hard    nproc           unlimited
EOF

# Kernel parameters for network performance
cat >> /etc/sysctl.conf << EOF

# DistriQueue optimizations
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
EOF

sysctl -p
