#!/bin/bash
# ==================================================
# Host Preparation Script for Nextcloud Server
# ==================================================
# This script prepares Ubuntu 24.04 for Nextcloud deployment
# Run as: sudo ./01-prepare-host.sh
# ==================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Nextcloud Host Preparation Script    ${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# ==================================================
# 1. System Update
# ==================================================
echo -e "\n${YELLOW}[1/8] Updating system packages...${NC}"
apt update && apt upgrade -y

# ==================================================
# 2. Install Required Packages
# ==================================================
echo -e "\n${YELLOW}[2/8] Installing required packages...${NC}"
apt install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    iotop \
    nfs-common \
    ca-certificates \
    gnupg \
    lsb-release \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-listchanges

# ==================================================
# 3. Install Docker
# ==================================================
echo -e "\n${YELLOW}[3/8] Installing Docker...${NC}"

# Remove old versions
apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
systemctl enable docker
systemctl start docker

# Add current user to docker group
if [ -n "$SUDO_USER" ]; then
    usermod -aG docker $SUDO_USER
    echo -e "${GREEN}Added $SUDO_USER to docker group${NC}"
fi

# ==================================================
# 4. Create Directory Structure
# ==================================================
echo -e "\n${YELLOW}[4/8] Creating directory structure...${NC}"

# NFS mount points
mkdir -p /mnt/nextcloud-data
mkdir -p /mnt/nextcloud-config

# Application directory
mkdir -p /opt/nextcloud/{configs/nginx,configs/php,configs/redis,db-data,redis-data,ssl}

# Set ownership
if [ -n "$SUDO_USER" ]; then
    chown -R $SUDO_USER:$SUDO_USER /opt/nextcloud
fi

echo -e "${GREEN}Created directories:${NC}"
echo "  /mnt/nextcloud-data"
echo "  /mnt/nextcloud-config"
echo "  /opt/nextcloud"

# ==================================================
# 5. Configure Firewall (UFW)
# ==================================================
echo -e "\n${YELLOW}[5/8] Configuring firewall...${NC}"

# Reset UFW
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow 22/tcp comment 'SSH'

# Allow HTTP/HTTPS
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Enable UFW
ufw --force enable

echo -e "${GREEN}Firewall configured:${NC}"
ufw status verbose

# ==================================================
# 6. Configure Fail2ban
# ==================================================
echo -e "\n${YELLOW}[6/8] Configuring Fail2ban...${NC}"

# Create Nextcloud filter
cat > /etc/fail2ban/filter.d/nextcloud.conf << 'EOF'
[Definition]
_groupsre = (?:(?:,?\s*"\w+":(?:"[^"]+"|\w+))*)
failregex = ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Login failed:
            ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Trusted domain error.
datepattern = ,?\s*"time"\s*:\s*"%%Y-%%m-%%d[T ]%%H:%%M:%%S(%%z)?"
EOF

# Create Nextcloud jail
cat > /etc/fail2ban/jail.d/nextcloud.conf << 'EOF'
[nextcloud]
backend = auto
enabled = true
port = 80,443
protocol = tcp
filter = nextcloud
maxretry = 5
bantime = 3600
findtime = 600
logpath = /mnt/nextcloud-data/nextcloud.log
EOF

# Restart Fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

echo -e "${GREEN}Fail2ban configured with Nextcloud filter${NC}"

# ==================================================
# 7. System Tuning
# ==================================================
echo -e "\n${YELLOW}[7/8] Applying system tuning...${NC}"

# Sysctl tuning
cat > /etc/sysctl.d/99-nextcloud.conf << 'EOF'
# Network tuning
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000

# NFS tuning
sunrpc.tcp_slot_table_entries = 128

# File system tuning
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

# Virtual memory tuning
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-nextcloud.conf

# Increase open file limits
cat > /etc/security/limits.d/99-nextcloud.conf << 'EOF'
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

echo -e "${GREEN}System tuning applied${NC}"

# ==================================================
# 8. Enable Automatic Updates
# ==================================================
echo -e "\n${YELLOW}[8/8] Configuring automatic security updates...${NC}"

# Configure unattended upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
    "docker-ce";
    "docker-ce-cli";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

echo -e "${GREEN}Automatic updates configured${NC}"

# ==================================================
# Summary
# ==================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Host Preparation Complete!           ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Configure NFS mounts: sudo ./02-mount-nfs.sh"
echo "  2. Copy docker files to /opt/nextcloud"
echo "  3. Edit /opt/nextcloud/.env"
echo "  4. Deploy: ./03-deploy.sh"
echo ""
echo -e "${YELLOW}NOTE: You may need to log out and back in for docker group to take effect${NC}"
