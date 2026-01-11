#!/bin/bash
# ==================================================
# Host Preparation Script for Nextcloud Server
# ==================================================
# This script prepares AlmaLinux 10 for Nextcloud deployment
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
echo -e "${GREEN}  Platform: AlmaLinux 10               ${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# ==================================================
# 1. System Update
# ==================================================
echo -e "\n${YELLOW}[1/9] Updating system packages...${NC}"
dnf update -y

# ==================================================
# 2. Install EPEL and Required Packages
# ==================================================
echo -e "\n${YELLOW}[2/9] Installing EPEL and required packages...${NC}"

# Enable EPEL
dnf install -y epel-release
dnf config-manager --set-enabled crb 2>/dev/null || true

# Install required packages
dnf install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    iotop \
    nfs-utils \
    ca-certificates \
    gnupg2 \
    tar \
    bzip2 \
    unzip \
    policycoreutils-python-utils \
    bash-completion \
    net-tools \
    bind-utils \
    fail2ban \
    fail2ban-firewalld \
    certbot \
    cronie

# ==================================================
# 3. Install Docker
# ==================================================
echo -e "\n${YELLOW}[3/9] Installing Docker...${NC}"

# Remove old versions
dnf remove -y docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    podman \
    runc 2>/dev/null || true

# Add Docker repository
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
systemctl enable --now docker

# Add current user to docker group
if [ -n "$SUDO_USER" ]; then
    usermod -aG docker $SUDO_USER
    echo -e "${GREEN}Added $SUDO_USER to docker group${NC}"
fi

# ==================================================
# 3b. Configure SELinux for Containers (after Docker install)
# ==================================================
echo -e "\n${YELLOW}[3b/9] Configuring SELinux for containers...${NC}"

# Now that container-selinux is installed with Docker, set container booleans
setsebool -P container_use_nfs 1 2>/dev/null || echo "  container_use_nfs not available"
setsebool -P container_manage_cgroup 1 2>/dev/null || echo "  container_manage_cgroup not available"

echo -e "${GREEN}SELinux container booleans configured${NC}"

# ==================================================
# 4. Create Directory Structure
# ==================================================
echo -e "\n${YELLOW}[4/9] Creating directory structure...${NC}"

# NFS mount points
mkdir -p /mnt/nextcloud-data
mkdir -p /mnt/nextcloud-config

# Application directory
mkdir -p /opt/nextcloud/{configs/nginx,configs/php,configs/redis,db-data,redis-data,ssl,backups}

# Set ownership
if [ -n "$SUDO_USER" ]; then
    chown -R $SUDO_USER:$SUDO_USER /opt/nextcloud
fi

echo -e "${GREEN}Created directories:${NC}"
echo "  /mnt/nextcloud-data"
echo "  /mnt/nextcloud-config"
echo "  /opt/nextcloud"

# ==================================================
# 5. Configure SELinux (Basic - NFS related)
# ==================================================
echo -e "\n${YELLOW}[5/9] Configuring SELinux...${NC}"

# Set SELinux booleans for NFS (container booleans will be set after Docker install)
setsebool -P httpd_use_nfs 1 2>/dev/null || echo "  httpd_use_nfs not available"
setsebool -P httpd_can_network_connect 1 2>/dev/null || echo "  httpd_can_network_connect not available"
setsebool -P httpd_can_network_connect_db 1 2>/dev/null || echo "  httpd_can_network_connect_db not available"
setsebool -P virt_use_nfs 1 2>/dev/null || echo "  virt_use_nfs not available"

echo -e "${GREEN}SELinux NFS booleans configured${NC}"

# ==================================================
# 6. Configure Firewall (firewalld)
# ==================================================
echo -e "\n${YELLOW}[6/9] Configuring firewall...${NC}"

# Ensure firewalld is running
systemctl enable --now firewalld

# Add services
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=ssh

# Remove unnecessary services
firewall-cmd --permanent --remove-service=cockpit 2>/dev/null || true
firewall-cmd --permanent --remove-service=dhcpv6-client 2>/dev/null || true

# Reload firewall
firewall-cmd --reload

echo -e "${GREEN}Firewall configured:${NC}"
firewall-cmd --list-all

# ==================================================
# 7. Configure Fail2ban
# ==================================================
echo -e "\n${YELLOW}[7/9] Configuring Fail2ban...${NC}"

# Create Nextcloud filter
cat > /etc/fail2ban/filter.d/nextcloud.conf << 'EOF'
[Definition]
_groupsre = (?:(?:,?\s*"\w+":(?:"[^"]+"|\w+))*)
failregex = ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Login failed:
            ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Trusted domain error.
datepattern = ,?\s*"time"\s*:\s*"%%Y-%%m-%%d[T ]%%H:%%M:%%S(%%z)?"
EOF

# Create Nextcloud jail
cat > /etc/fail2ban/jail.d/nextcloud.local << 'EOF'
[nextcloud]
backend = auto
enabled = true
port = http,https
protocol = tcp
filter = nextcloud
maxretry = 5
bantime = 86400
findtime = 600
logpath = /mnt/nextcloud-data/nextcloud.log
banaction = firewallcmd-rich-rules[actiontype=<multiport>]
banaction_allports = firewallcmd-rich-rules[actiontype=<allports>]
EOF

# Create SSH jail
cat > /etc/fail2ban/jail.d/sshd.local << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 3
bantime = 86400
findtime = 600
banaction = firewallcmd-rich-rules[actiontype=<multiport>]
EOF

# Start Fail2ban
systemctl enable --now fail2ban

echo -e "${GREEN}Fail2ban configured with Nextcloud filter${NC}"

# ==================================================
# 8. System Tuning
# ==================================================
echo -e "\n${YELLOW}[8/9] Applying system tuning...${NC}"

# Sysctl tuning
cat > /etc/sysctl.d/99-nextcloud.conf << 'EOF'
# Network tuning
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 65535

# File system tuning
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

# Virtual memory tuning
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
EOF

# Apply sysctl settings (ignore errors for unavailable parameters)
sysctl -p /etc/sysctl.d/99-nextcloud.conf 2>/dev/null || true

# NFS tuning (sunrpc module may not be loaded yet)
# This will be applied when NFS is first used
cat > /etc/sysctl.d/99-nfs-tuning.conf << 'EOF'
# NFS tuning - applied when sunrpc module is loaded
sunrpc.tcp_slot_table_entries = 128
EOF

# Try to load sunrpc module and apply NFS tuning
modprobe sunrpc 2>/dev/null || true
sysctl -p /etc/sysctl.d/99-nfs-tuning.conf 2>/dev/null || echo "  sunrpc tuning will be applied after first NFS mount"

# Increase open file limits
cat > /etc/security/limits.d/99-nextcloud.conf << 'EOF'
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

echo -e "${GREEN}System tuning applied${NC}"

# ==================================================
# 9. Enable NFS Client Services
# ==================================================
echo -e "\n${YELLOW}[9/9] Enabling NFS client services...${NC}"

systemctl enable --now nfs-client.target
systemctl enable --now rpcbind

echo -e "${GREEN}NFS client services enabled${NC}"

# ==================================================
# Configure DNF Automatic Updates (Security Only)
# ==================================================
echo -e "\n${YELLOW}Configuring automatic security updates...${NC}"

dnf install -y dnf-automatic

# Configure for security updates only
cat > /etc/dnf/automatic.conf << 'EOF'
[commands]
upgrade_type = security
random_sleep = 360
download_updates = yes
apply_updates = yes

[emitters]
emit_via = stdio

[email]
email_from = root@localhost
email_to = root
email_host = localhost

[command]
[command_email]
[base]
debuglevel = 1
EOF

systemctl enable --now dnf-automatic.timer

echo -e "${GREEN}Automatic security updates configured${NC}"

# ==================================================
# Summary
# ==================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Host Preparation Complete!           ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Installed components:"
echo "  ✓ Docker CE + Docker Compose"
echo "  ✓ NFS client utilities"
echo "  ✓ Fail2ban with Nextcloud filter"
echo "  ✓ Firewalld (HTTP/HTTPS/SSH)"
echo "  ✓ SELinux booleans configured"
echo "  ✓ System performance tuning"
echo "  ✓ Automatic security updates"
echo ""
echo "Next steps:"
echo "  1. Configure NFS mounts: sudo ./02-mount-nfs.sh"
echo "  2. Copy docker files to /opt/nextcloud"
echo "  3. Edit /opt/nextcloud/.env"
echo "  4. Deploy: ./03-deploy.sh"
echo ""
echo -e "${YELLOW}NOTE: You may need to log out and back in for docker group to take effect${NC}"
