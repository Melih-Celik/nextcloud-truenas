#!/bin/bash
# ==================================================
# NFS Mount Script for TrueNAS Integration
# ==================================================
# This script mounts NFS shares from TrueNAS
# Platform: AlmaLinux 10
# Run as: sudo ./02-mount-nfs.sh
# ==================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  NFS Mount Configuration Script       ${NC}"
echo -e "${GREEN}  Platform: AlmaLinux 10               ${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# ==================================================
# Configuration - UPDATE THESE VALUES
# ==================================================
TRUENAS_IP="${TRUENAS_IP:-192.168.1.20}"
DATA_EXPORT="/mnt/storage/nextcloud/data"
CONFIG_EXPORT="/mnt/storage/nextcloud/config"
DATA_MOUNT="/mnt/nextcloud-data"
CONFIG_MOUNT="/mnt/nextcloud-config"

# NFS Mount Options (optimized for performance)
NFS_OPTS="rw,hard,intr,rsize=1048576,wsize=1048576,timeo=600,retrans=2,_netdev"

# ==================================================
# 1. Check NFS Client
# ==================================================
echo -e "\n${YELLOW}[1/6] Checking NFS client...${NC}"

if ! rpm -q nfs-utils &> /dev/null; then
    echo "Installing nfs-utils..."
    dnf install -y nfs-utils
fi

# Ensure services are running
systemctl enable --now nfs-client.target
systemctl enable --now rpcbind

echo -e "${GREEN}NFS client is installed and running${NC}"

# ==================================================
# 2. Check SELinux
# ==================================================
echo -e "\n${YELLOW}[2/6] Checking SELinux configuration...${NC}"

# Set SELinux booleans for NFS (ignore errors if not available)
setsebool -P container_use_nfs 1 2>/dev/null || true
setsebool -P httpd_use_nfs 1 2>/dev/null || true
setsebool -P virt_use_nfs 1 2>/dev/null || true

if getenforce 2>/dev/null | grep -q "Enforcing"; then
    echo -e "${GREEN}SELinux is enforcing - NFS booleans configured${NC}"
elif getenforce 2>/dev/null | grep -q "Permissive"; then
    echo -e "${YELLOW}SELinux is permissive${NC}"
else
    echo -e "${YELLOW}SELinux status unknown or disabled${NC}"
fi

# ==================================================
# 3. Test TrueNAS Connection
# ==================================================
echo -e "\n${YELLOW}[3/6] Testing TrueNAS connection...${NC}"

if ! ping -c 1 -W 2 $TRUENAS_IP &> /dev/null; then
    echo -e "${RED}Cannot reach TrueNAS at $TRUENAS_IP${NC}"
    echo "Please check:"
    echo "  1. TrueNAS IP address is correct"
    echo "  2. Network connectivity"
    echo "  3. Firewall rules"
    exit 1
fi

echo -e "${GREEN}TrueNAS is reachable at $TRUENAS_IP${NC}"

# ==================================================
# 4. Check NFS Exports
# ==================================================
echo -e "\n${YELLOW}[4/6] Checking NFS exports on TrueNAS...${NC}"

echo "Available exports from $TRUENAS_IP:"
if ! showmount -e $TRUENAS_IP; then
    echo -e "${RED}Failed to get NFS exports from TrueNAS${NC}"
    echo "Please check:"
    echo "  1. NFS service is running on TrueNAS"
    echo "  2. NFS shares are configured"
    echo "  3. This server IP is in the allowed hosts"
    exit 1
fi

# ==================================================
# 5. Create Mount Points and Test
# ==================================================
echo -e "\n${YELLOW}[5/6] Setting up mount points...${NC}"

# Create mount directories
mkdir -p $DATA_MOUNT
mkdir -p $CONFIG_MOUNT

# Test mount for data
echo "Testing mount for data directory..."
if mount -t nfs4 $TRUENAS_IP:$DATA_EXPORT $DATA_MOUNT -o $NFS_OPTS; then
    echo -e "${GREEN}Data mount successful!${NC}"
    
    # Test write
    if touch $DATA_MOUNT/.mount_test 2>/dev/null; then
        rm $DATA_MOUNT/.mount_test
        echo -e "${GREEN}Write test passed${NC}"
    else
        echo -e "${YELLOW}Warning: Cannot write to data mount. Check permissions on TrueNAS.${NC}"
    fi
    
    # Unmount for fstab configuration
    umount $DATA_MOUNT
else
    echo -e "${RED}Failed to mount data directory${NC}"
    exit 1
fi

# Test mount for config
echo "Testing mount for config directory..."
if mount -t nfs4 $TRUENAS_IP:$CONFIG_EXPORT $CONFIG_MOUNT -o $NFS_OPTS; then
    echo -e "${GREEN}Config mount successful!${NC}"
    umount $CONFIG_MOUNT
else
    echo -e "${RED}Failed to mount config directory${NC}"
    exit 1
fi

# ==================================================
# 6. Configure /etc/fstab
# ==================================================
echo -e "\n${YELLOW}[6/6] Configuring /etc/fstab...${NC}"

# Backup fstab
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)

# Check if entries already exist
if grep -q "$DATA_MOUNT" /etc/fstab; then
    echo -e "${YELLOW}Data mount entry already exists in fstab, skipping...${NC}"
else
    echo "# Nextcloud Data - TrueNAS NFS" >> /etc/fstab
    echo "$TRUENAS_IP:$DATA_EXPORT    $DATA_MOUNT    nfs4    $NFS_OPTS    0    0" >> /etc/fstab
    echo -e "${GREEN}Added data mount to fstab${NC}"
fi

if grep -q "$CONFIG_MOUNT" /etc/fstab; then
    echo -e "${YELLOW}Config mount entry already exists in fstab, skipping...${NC}"
else
    echo "# Nextcloud Config - TrueNAS NFS" >> /etc/fstab
    echo "$TRUENAS_IP:$CONFIG_EXPORT    $CONFIG_MOUNT    nfs4    $NFS_OPTS    0    0" >> /etc/fstab
    echo -e "${GREEN}Added config mount to fstab${NC}"
fi

# Mount all
echo "Mounting all filesystems..."
mount -a

# Verify mounts
echo -e "\n${GREEN}Current NFS mounts:${NC}"
df -h | grep -E "(Filesystem|nextcloud)"

# ==================================================
# Summary
# ==================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  NFS Mount Configuration Complete!    ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Mount points:"
echo "  Data:   $DATA_MOUNT"
echo "  Config: $CONFIG_MOUNT"
echo ""
echo "fstab entries added. Mounts will persist after reboot."
echo ""
echo "Next step: Deploy Nextcloud with ./03-deploy.sh"
