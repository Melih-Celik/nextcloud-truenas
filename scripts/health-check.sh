#!/bin/bash
# ==================================================
# Nextcloud Health Check Script
# ==================================================
# Monitors system health and reports issues
# Run as: ./health-check.sh
# ==================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_DIR/.install-config"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Configuration from config file or defaults
PROJECT_DIR="${PROJECT_DIR:-/opt/nextcloud}"
TRUENAS_IP="${TRUENAS_IP:-192.168.1.20}"
NFS_DATA_MOUNT="${NFS_DATA_MOUNT:-/mnt/nextcloud-data}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Nextcloud System Health Check        ${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Timestamp: $(date)"
echo ""
echo "Configuration:"
echo "  Project Dir  : $PROJECT_DIR"
echo "  TrueNAS IP   : $TRUENAS_IP"
echo "  Data Mount   : $NFS_DATA_MOUNT"
echo ""

ERRORS=0
WARNINGS=0

# ==================================================
# Docker Services
# ==================================================
echo -e "${YELLOW}[Docker Services]${NC}"

cd $PROJECT_DIR 2>/dev/null || { echo -e "${RED}Cannot access $PROJECT_DIR${NC}"; exit 1; }

SERVICES="nginx nextcloud postgres redis nextcloud-cron"
for SERVICE in $SERVICES; do
    STATUS=$(docker inspect -f '{{.State.Status}}' $SERVICE 2>/dev/null || echo "not found")
    if [ "$STATUS" == "running" ]; then
        echo -e "  $SERVICE: ${GREEN}✓ Running${NC}"
    else
        echo -e "  $SERVICE: ${RED}✗ $STATUS${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

# ==================================================
# NFS Mounts
# ==================================================
echo -e "\n${YELLOW}[NFS Mounts]${NC}"

if mountpoint -q "$NFS_DATA_MOUNT"; then
    SIZE=$(df -h "$NFS_DATA_MOUNT" | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')
    echo -e "  Data mount: ${GREEN}✓ Mounted${NC} - $SIZE"
else
    echo -e "  Data mount: ${RED}✗ Not mounted${NC}"
    ERRORS=$((ERRORS + 1))
fi

# ==================================================
# TrueNAS Connection
# ==================================================
echo -e "\n${YELLOW}[TrueNAS Connection]${NC}"

if ping -c 1 -W 2 $TRUENAS_IP &> /dev/null; then
    echo -e "  Network: ${GREEN}✓ Reachable${NC}"
else
    echo -e "  Network: ${RED}✗ Unreachable${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check NFS port
if nc -z -w2 $TRUENAS_IP 2049 2>/dev/null; then
    echo -e "  NFS Service: ${GREEN}✓ Available${NC}"
else
    echo -e "  NFS Service: ${RED}✗ Unavailable${NC}"
    ERRORS=$((ERRORS + 1))
fi

# ==================================================
# Nextcloud Status
# ==================================================
echo -e "\n${YELLOW}[Nextcloud Status]${NC}"

# Check if Nextcloud is in maintenance mode
MAINT_MODE=$(docker exec -u www-data nextcloud php occ maintenance:mode 2>/dev/null | grep -c "enabled" || echo "0")
if [ "$MAINT_MODE" == "1" ]; then
    echo -e "  Maintenance Mode: ${YELLOW}⚠ Enabled${NC}"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "  Maintenance Mode: ${GREEN}✓ Disabled${NC}"
fi

# Get Nextcloud status
NC_STATUS=$(docker exec -u www-data nextcloud php occ status --output=json 2>/dev/null || echo '{}')
NC_VERSION=$(echo $NC_STATUS | grep -o '"versionstring":"[^"]*"' | cut -d'"' -f4)
NC_INSTALLED=$(echo $NC_STATUS | grep -o '"installed":true')

if [ -n "$NC_INSTALLED" ]; then
    echo -e "  Installation: ${GREEN}✓ Complete${NC}"
    echo -e "  Version: $NC_VERSION"
else
    echo -e "  Installation: ${RED}✗ Not installed${NC}"
    ERRORS=$((ERRORS + 1))
fi

# ==================================================
# Database Status
# ==================================================
echo -e "\n${YELLOW}[Database (PostgreSQL)]${NC}"

if docker exec postgres pg_isready -U nextcloud -d nextcloud &>/dev/null; then
    echo -e "  Connection: ${GREEN}✓ Ready${NC}"
    
    # Get database size
    DB_SIZE=$(docker exec postgres psql -U nextcloud -d nextcloud -t -c "SELECT pg_size_pretty(pg_database_size('nextcloud'));" 2>/dev/null | xargs)
    echo -e "  Size: $DB_SIZE"
else
    echo -e "  Connection: ${RED}✗ Not ready${NC}"
    ERRORS=$((ERRORS + 1))
fi

# ==================================================
# Redis Status
# ==================================================
echo -e "\n${YELLOW}[Cache (Redis)]${NC}"

# Get Redis password from .env
REDIS_PASS=$(grep REDIS_PASSWORD .env 2>/dev/null | cut -d'=' -f2)

if docker exec redis redis-cli -a "$REDIS_PASS" ping 2>/dev/null | grep -q "PONG"; then
    echo -e "  Connection: ${GREEN}✓ Connected${NC}"
    
    # Get memory usage
    REDIS_MEM=$(docker exec redis redis-cli -a "$REDIS_PASS" info memory 2>/dev/null | grep "used_memory_human" | cut -d':' -f2 | tr -d '\r')
    echo -e "  Memory: $REDIS_MEM"
else
    echo -e "  Connection: ${RED}✗ Not connected${NC}"
    ERRORS=$((ERRORS + 1))
fi

# ==================================================
# SSL Certificate
# ==================================================
echo -e "\n${YELLOW}[SSL Certificate]${NC}"

if [ -f "$PROJECT_DIR/ssl/fullchain.pem" ]; then
    CERT_EXPIRY=$(openssl x509 -enddate -noout -in $PROJECT_DIR/ssl/fullchain.pem 2>/dev/null | cut -d'=' -f2)
    CERT_DAYS=$(( ( $(date -d "$CERT_EXPIRY" +%s) - $(date +%s) ) / 86400 ))
    
    if [ $CERT_DAYS -gt 30 ]; then
        echo -e "  Status: ${GREEN}✓ Valid${NC}"
        echo -e "  Expires: $CERT_EXPIRY ($CERT_DAYS days)"
    elif [ $CERT_DAYS -gt 0 ]; then
        echo -e "  Status: ${YELLOW}⚠ Expiring soon${NC}"
        echo -e "  Expires: $CERT_EXPIRY ($CERT_DAYS days)"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "  Status: ${RED}✗ Expired${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "  Status: ${YELLOW}⚠ Certificate not found${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# ==================================================
# Disk Space
# ==================================================
echo -e "\n${YELLOW}[Disk Space]${NC}"

# Local disk
LOCAL_USE=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
LOCAL_SIZE=$(df -h / | tail -1 | awk '{print $3 "/" $2}')
if [ $LOCAL_USE -lt 80 ]; then
    echo -e "  Local (/): ${GREEN}✓ $LOCAL_SIZE ($LOCAL_USE%)${NC}"
elif [ $LOCAL_USE -lt 90 ]; then
    echo -e "  Local (/): ${YELLOW}⚠ $LOCAL_SIZE ($LOCAL_USE%)${NC}"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "  Local (/): ${RED}✗ $LOCAL_SIZE ($LOCAL_USE%)${NC}"
    ERRORS=$((ERRORS + 1))
fi

# NFS data
if mountpoint -q "$NFS_DATA_MOUNT"; then
    NFS_USE=$(df -h "$NFS_DATA_MOUNT" | tail -1 | awk '{print $5}' | tr -d '%')
    NFS_SIZE=$(df -h "$NFS_DATA_MOUNT" | tail -1 | awk '{print $3 "/" $2}')
    if [ $NFS_USE -lt 80 ]; then
        echo -e "  NFS Data: ${GREEN}✓ $NFS_SIZE ($NFS_USE%)${NC}"
    elif [ $NFS_USE -lt 90 ]; then
        echo -e "  NFS Data: ${YELLOW}⚠ $NFS_SIZE ($NFS_USE%)${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "  NFS Data: ${RED}✗ $NFS_SIZE ($NFS_USE%)${NC}"
        ERRORS=$((ERRORS + 1))
    fi
fi

# ==================================================
# Background Jobs
# ==================================================
echo -e "\n${YELLOW}[Background Jobs]${NC}"

LAST_CRON=$(docker exec -u www-data nextcloud php occ background:cron 2>/dev/null | grep -i "last" || echo "Unknown")
echo -e "  Cron: $LAST_CRON"

# ==================================================
# Summary
# ==================================================
echo -e "\n${GREEN}========================================${NC}"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}  ✓ All systems healthy!              ${NC}"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}  ⚠ $WARNINGS warning(s) detected        ${NC}"
else
    echo -e "${RED}  ✗ $ERRORS error(s), $WARNINGS warning(s)   ${NC}"
fi
echo -e "${GREEN}========================================${NC}"

exit $ERRORS
