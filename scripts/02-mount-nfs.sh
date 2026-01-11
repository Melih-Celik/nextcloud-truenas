#!/bin/bash
# ==================================================
# NFS Mount Script for TrueNAS Integration
# ==================================================
# This script mounts 3 NFS shares from TrueNAS:
#   - config   : Nextcloud configuration
#   - data     : User data (60TB+)
#   - database : PostgreSQL database
# Platform: AlmaLinux 10
# Run as: sudo ./02-mount-nfs.sh
# ==================================================

set -e

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
    echo -e "${BLUE}ℹ${NC} Yapılandırma dosyası yüklendi: $CONFIG_FILE"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  NFS Mount Configuration Script       ${NC}"
echo -e "${GREEN}  TrueNAS 3-Mount Setup                ${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# ==================================================
# Configuration - from config file or defaults
# ==================================================
TRUENAS_IP="${TRUENAS_IP:-192.168.1.20}"

# NFS Base paths
NFS_BASE_EXPORT="${NFS_BASE_EXPORT:-/mnt/storage/nextcloud}"
NFS_BASE_MOUNT="${NFS_BASE_MOUNT:-/mnt/nextcloud}"

# Individual exports (only config and data - database is local)
NFS_CONFIG_EXPORT="${NFS_CONFIG_EXPORT:-$NFS_BASE_EXPORT/config}"
NFS_DATA_EXPORT="${NFS_DATA_EXPORT:-$NFS_BASE_EXPORT/data}"

# Individual mount points
NFS_CONFIG_MOUNT="${NFS_CONFIG_MOUNT:-$NFS_BASE_MOUNT/config}"
NFS_DATA_MOUNT="${NFS_DATA_MOUNT:-$NFS_BASE_MOUNT/data}"

# Show current configuration
echo ""
echo -e "${YELLOW}Yapilandirma:${NC}"
echo "  TrueNAS IP     : $TRUENAS_IP"
echo ""
echo "  NFS Exports:"
echo "    Config       : $NFS_CONFIG_EXPORT"
echo "    Data         : $NFS_DATA_EXPORT"
echo ""
echo "  Mount Noktalari:"
echo "    Config       : $NFS_CONFIG_MOUNT"
echo "    Data         : $NFS_DATA_MOUNT"
echo ""
echo -e "${BLUE}Not: PostgreSQL veritabani performans icin yerel diskte tutulur.${NC}"
echo ""

# NFS Mount Options (optimized for 60TB+ data)
# Hard mount ensures data integrity
NFS_OPTS="rw,hard,intr,rsize=1048576,wsize=1048576,timeo=600,retrans=2,_netdev,nofail"

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
# 5. Create Mount Points
# ==================================================
echo -e "\n${YELLOW}[5/6] Creating mount points...${NC}"

mkdir -p "$NFS_CONFIG_MOUNT"
mkdir -p "$NFS_DATA_MOUNT"

echo -e "${GREEN}Mount points created${NC}"

# ==================================================
# 6. Mount and Configure fstab
# ==================================================
echo -e "\n${YELLOW}[6/6] Mounting NFS shares and configuring fstab...${NC}"

# Backup fstab
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
echo "fstab backup created"

# Function to mount and add to fstab
mount_nfs() {
    local export_path="$1"
    local mount_point="$2"
    local mount_opts="$3"
    local name="$4"
    
    echo ""
    echo -e "${BLUE}Mounting $name...${NC}"
    
    # Check if already mounted
    if mountpoint -q "$mount_point"; then
        echo -e "${YELLOW}  $name is already mounted${NC}"
        return 0
    fi
    
    # Test mount
    if mount -t nfs4 "$TRUENAS_IP:$export_path" "$mount_point" -o "$mount_opts"; then
        echo -e "${GREEN}  ✓ $name mounted successfully${NC}"
        
        # Test write
        if touch "$mount_point/.mount_test" 2>/dev/null; then
            rm "$mount_point/.mount_test"
            echo -e "${GREEN}  ✓ Write test passed${NC}"
        else
            echo -e "${YELLOW}  ⚠ Cannot write to $name. Check TrueNAS permissions.${NC}"
        fi
        
        # Unmount for fstab configuration
        umount "$mount_point"
    else
        echo -e "${RED}  ✗ Failed to mount $name${NC}"
        return 1
    fi
    
    # Add to fstab if not exists
    if grep -q "$mount_point" /etc/fstab; then
        echo -e "${YELLOW}  fstab entry already exists for $name${NC}"
    else
        echo "# Nextcloud $name - TrueNAS NFS" >> /etc/fstab
        echo "$TRUENAS_IP:$export_path    $mount_point    nfs4    $mount_opts    0    0" >> /etc/fstab
        echo -e "${GREEN}  ✓ Added $name to fstab${NC}"
    fi
}

# Mount config and data shares (database is local)
mount_nfs "$NFS_CONFIG_EXPORT" "$NFS_CONFIG_MOUNT" "$NFS_OPTS" "Config"
mount_nfs "$NFS_DATA_EXPORT" "$NFS_DATA_MOUNT" "$NFS_OPTS" "Data"

# Mount all from fstab
echo ""
echo "Mounting all filesystems from fstab..."
mount -a

# ==================================================
# Verify mounts
# ==================================================
echo -e "\n${GREEN}Verifying mounts...${NC}"

verify_mount() {
    local mount_point="$1"
    local name="$2"
    
    if mountpoint -q "$mount_point"; then
        echo -e "${GREEN}  ✓ $name mounted at $mount_point${NC}"
    else
        echo -e "${RED}  ✗ $name NOT mounted at $mount_point${NC}"
        return 1
    fi
}

echo ""
verify_mount "$NFS_CONFIG_MOUNT" "Config"
verify_mount "$NFS_DATA_MOUNT" "Data"

# Show disk space
echo -e "\n${YELLOW}Disk Space:${NC}"
df -h | grep -E "(Filesystem|nextcloud)"

# ==================================================
# Set Permissions (www-data UID:GID for Alpine)
# ==================================================
echo -e "\n${YELLOW}Setting permissions for www-data (UID:82)...${NC}"

# www-data in Alpine is UID/GID 82
WWW_DATA_UID=82
WWW_DATA_GID=82

# Set ownership
chown -R $WWW_DATA_UID:$WWW_DATA_GID "$NFS_CONFIG_MOUNT" 2>/dev/null || echo "  Note: chown on NFS may need TrueNAS ACL configuration"
chown -R $WWW_DATA_UID:$WWW_DATA_GID "$NFS_DATA_MOUNT" 2>/dev/null || true

echo -e "${GREEN}Permissions set${NC}"

# ==================================================
# Summary
# ==================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  NFS Mount Configuration Complete!    ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Mount points configured:"
echo "  Config   : $NFS_CONFIG_MOUNT"
echo "  Data     : $NFS_DATA_MOUNT"
echo ""
echo -e "${BLUE}Note: PostgreSQL database is stored locally for performance.${NC}"
echo ""
echo "fstab entries added. Mounts will persist after reboot."
echo ""
echo -e "${YELLOW}TrueNAS yetkilendirme ayarlari:${NC}"
echo "  1. Her dataset icin maproot=root veya mapall=nobody:nogroup"
echo "  2. Veya ACL ile www-data (UID:82) izni verin"
echo ""
echo "Next step: Deploy Nextcloud with ./03-deploy.sh"
