#!/bin/bash

BACKUP_DIR="/opt/distriqueue/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup H2 database
cp -r /opt/distriqueue/data/h2 $BACKUP_DIR/

# Backup RabbitMQ definitions
rabbitmqctl export_definitions $BACKUP_DIR/rabbitmq-definitions.json

# Backup Redis
redis-cli -a RedisPass123! SAVE
cp /var/lib/redis/dump.rdb $BACKUP_DIR/

# Backup configurations
cp -r /opt/distriqueue/config $BACKUP_DIR/

# Compress backup
tar -czf $BACKUP_DIR.tar.gz $BACKUP_DIR
rm -rf $BACKUP_DIR

echo "Backup completed: $BACKUP_DIR.tar.gz"
