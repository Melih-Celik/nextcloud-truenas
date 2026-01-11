#!/bin/bash
# ==================================================
# Nextcloud Backup Script
# ==================================================
# Backs up Nextcloud database, config, and creates 
# ZFS snapshot on TrueNAS
# Run as: sudo ./backup.sh
# ==================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/opt/nextcloud/backups}"
TRUENAS_IP="${TRUENAS_IP:-192.168.1.20}"
TRUENAS_USER="${TRUENAS_USER:-admin}"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Nextcloud Backup Script              ${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Backup started at: $(date)"

# Create backup directory
mkdir -p $BACKUP_DIR

# ==================================================
# 1. Enable Maintenance Mode
# ==================================================
echo -e "\n${YELLOW}[1/5] Enabling maintenance mode...${NC}"
docker exec -u www-data nextcloud php occ maintenance:mode --on

# ==================================================
# 2. Database Backup
# ==================================================
echo -e "\n${YELLOW}[2/5] Backing up database...${NC}"

docker exec postgres pg_dump -U nextcloud nextcloud | gzip > $BACKUP_DIR/db_backup_$DATE.sql.gz

echo -e "${GREEN}Database backed up to: db_backup_$DATE.sql.gz${NC}"

# ==================================================
# 3. Config Backup
# ==================================================
echo -e "\n${YELLOW}[3/5] Backing up configuration...${NC}"

# Backup Nextcloud config
tar -czf $BACKUP_DIR/config_backup_$DATE.tar.gz -C /mnt nextcloud-config

# Backup Docker config
tar -czf $BACKUP_DIR/docker_config_$DATE.tar.gz -C /opt/nextcloud .env docker-compose.yml configs

echo -e "${GREEN}Config backed up${NC}"

# ==================================================
# 4. TrueNAS ZFS Snapshot (via SSH)
# ==================================================
echo -e "\n${YELLOW}[4/5] Creating ZFS snapshot on TrueNAS...${NC}"

SNAPSHOT_NAME="backup-$DATE"

# Check if SSH key exists for passwordless auth
if [ -f ~/.ssh/id_rsa ]; then
    # Create snapshot via SSH
    if ssh -o ConnectTimeout=10 $TRUENAS_USER@$TRUENAS_IP \
        "zfs snapshot -r storage/nextcloud@$SNAPSHOT_NAME" 2>/dev/null; then
        echo -e "${GREEN}ZFS snapshot created: storage/nextcloud@$SNAPSHOT_NAME${NC}"
    else
        echo -e "${YELLOW}Warning: Could not create ZFS snapshot via SSH${NC}"
        echo "You may need to:"
        echo "  1. Set up SSH key authentication"
        echo "  2. Or create snapshot manually on TrueNAS"
    fi
else
    echo -e "${YELLOW}SSH key not found. Skipping remote ZFS snapshot.${NC}"
    echo "To enable, run: ssh-keygen && ssh-copy-id $TRUENAS_USER@$TRUENAS_IP"
fi

# ==================================================
# 5. Disable Maintenance Mode
# ==================================================
echo -e "\n${YELLOW}[5/5] Disabling maintenance mode...${NC}"
docker exec -u www-data nextcloud php occ maintenance:mode --off

# ==================================================
# Cleanup Old Backups
# ==================================================
echo -e "\n${YELLOW}Cleaning up old backups (older than $RETENTION_DAYS days)...${NC}"

find $BACKUP_DIR -name "*.gz" -type f -mtime +$RETENTION_DAYS -delete
find $BACKUP_DIR -name "*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete

# ==================================================
# Summary
# ==================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Backup Complete!                     ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Backup files:"
ls -lh $BACKUP_DIR/*$DATE* 2>/dev/null || echo "Check $BACKUP_DIR"
echo ""
echo "Backup completed at: $(date)"

# Calculate backup size
BACKUP_SIZE=$(du -sh $BACKUP_DIR | cut -f1)
echo "Total backup directory size: $BACKUP_SIZE"
