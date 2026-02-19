#!/bin/bash

echo "Configuring /etc/hosts..."

cat >> /etc/hosts << EOF
10.2.1.11 Adrien0.local Adrien0
10.2.1.12 Adrien1.local Adrien1
EOF
