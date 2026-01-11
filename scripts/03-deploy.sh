#!/bin/bash
# ==================================================
# Nextcloud Deployment Script
# ==================================================
# This script deploys Nextcloud using Docker Compose
# Run as: ./03-deploy.sh
# ==================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_DIR/.install-config"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${BLUE}ℹ${NC} Yapılandırma dosyası yüklendi: $CONFIG_FILE"
fi

# Default values (can be overridden by config file)
PROJECT_DIR="${PROJECT_DIR:-/opt/nextcloud}"
NFS_DATA_MOUNT="${NFS_DATA_MOUNT:-/mnt/nextcloud-data}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Nextcloud Deployment Script          ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Proje Dizini : $PROJECT_DIR"
echo "  Data Mount   : $NFS_DATA_MOUNT"
echo ""

# ==================================================
# Pre-flight Checks
# ==================================================
echo -e "\n${YELLOW}[1/6] Running pre-flight checks...${NC}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Run 01-prepare-host.sh first.${NC}"
    exit 1
fi

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    echo -e "${RED}Docker Compose is not available.${NC}"
    exit 1
fi

# Check NFS mounts
if ! mountpoint -q "$NFS_DATA_MOUNT"; then
    echo -e "${RED}NFS data mount is not available at $NFS_DATA_MOUNT. Run 02-mount-nfs.sh first.${NC}"
    exit 1
fi

echo -e "${GREEN}All pre-flight checks passed!${NC}"

# ==================================================
# Copy Docker Files to Project Directory
# ==================================================
echo -e "\n${YELLOW}[2/6] Copying Docker files to $PROJECT_DIR...${NC}"

# Find the docker directory (relative to this script)
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$REPO_DIR/docker"

if [ ! -d "$DOCKER_DIR" ]; then
    echo -e "${RED}Docker files not found at $DOCKER_DIR${NC}"
    exit 1
fi

# Create project directory if it doesn't exist
sudo mkdir -p "$PROJECT_DIR"
sudo chown $(whoami):$(whoami) "$PROJECT_DIR"

# Copy docker-compose.yml
cp "$DOCKER_DIR/docker-compose.yml" "$PROJECT_DIR/"
echo "  Copied docker-compose.yml"

# Copy NPM compose file if NPM is configured
if [ "${INSTALL_NPM:-false}" = "true" ] && [ -f "$DOCKER_DIR/docker-compose.npm.yml" ]; then
    cp "$DOCKER_DIR/docker-compose.npm.yml" "$PROJECT_DIR/"
    echo "  Copied docker-compose.npm.yml (NPM enabled)"
fi

# Copy Collabora compose file if configured
if [ "${INSTALL_COLLABORA:-false}" = "true" ] && [ -f "$DOCKER_DIR/docker-compose.collabora.yml" ]; then
    cp "$DOCKER_DIR/docker-compose.collabora.yml" "$PROJECT_DIR/"
    echo "  Copied docker-compose.collabora.yml (Collabora enabled)"
fi

# Copy override file if exists
if [ -f "$DOCKER_DIR/docker-compose.override.yml" ]; then
    cp "$DOCKER_DIR/docker-compose.override.yml" "$PROJECT_DIR/"
    echo "  Copied docker-compose.override.yml"
fi

# Copy configs directory (preserve permissions for hook scripts)
mkdir -p "$PROJECT_DIR/configs"
cp -rp "$DOCKER_DIR/configs/"* "$PROJECT_DIR/configs/" 2>/dev/null || true
echo "  Copied configs/"

# Ensure hook scripts are executable
find "$PROJECT_DIR/configs/nextcloud/hooks" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# Create necessary directories
mkdir -p "$PROJECT_DIR/db-data"
mkdir -p "$PROJECT_DIR/redis-data"

echo -e "${GREEN}Docker files copied${NC}"

# ==================================================
# Configure Environment
# ==================================================
echo -e "\n${YELLOW}[3/6] Configuring environment...${NC}"

cd "$PROJECT_DIR"

# www-data user UID:GID (Nextcloud default)
WWW_DATA_UID=33
WWW_DATA_GID=33

# Create .env if it doesn't exist
if [ ! -f ".env" ]; then
    # Check for .env in docker directory first
    if [ -f "$DOCKER_DIR/.env" ]; then
        cp "$DOCKER_DIR/.env" "$PROJECT_DIR/.env"
        echo "  Created .env from docker/.env"
    elif [ -f "$DOCKER_DIR/.env.example" ]; then
        cp "$DOCKER_DIR/.env.example" "$PROJECT_DIR/.env"
        echo "  Created .env from template"
        
        # Generate random passwords
        POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
        REDIS_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
        NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 16)
        
        # Replace placeholder passwords
        sed -i "s/POSTGRES_PASSWORD=CHANGE_ME/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" "$PROJECT_DIR/.env"
        sed -i "s/REDIS_PASSWORD=CHANGE_ME/REDIS_PASSWORD=$REDIS_PASSWORD/" "$PROJECT_DIR/.env"
        sed -i "s/NEXTCLOUD_ADMIN_PASSWORD=CHANGE_ME/NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD/" "$PROJECT_DIR/.env"
        
        echo -e "${GREEN}  Generated random passwords${NC}"
        echo ""
        echo -e "${YELLOW}  IMPORTANT: Save these credentials!${NC}"
        echo "  PostgreSQL Password: $POSTGRES_PASSWORD"
        echo "  Redis Password: $REDIS_PASSWORD"
        echo "  Nextcloud Admin Password: $NEXTCLOUD_ADMIN_PASSWORD"
        echo ""
        echo "  Credentials saved in: $PROJECT_DIR/.env"
    else
        echo -e "${RED}.env file not found. Please run setup.sh first or copy .env.example${NC}"
        exit 1
    fi
else
    echo "  .env file already exists"
fi

# Verify no CHANGE_ME placeholders remain
if grep -q "CHANGE_ME" "$PROJECT_DIR/.env"; then
    echo -e "${YELLOW}Found 'CHANGE_ME' in .env, generating replacement...${NC}"
    
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    REDIS_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 16)
    
    sed -i "s/POSTGRES_PASSWORD=CHANGE_ME/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" "$PROJECT_DIR/.env"
    sed -i "s/REDIS_PASSWORD=CHANGE_ME/REDIS_PASSWORD=$REDIS_PASSWORD/" "$PROJECT_DIR/.env"
    sed -i "s/NEXTCLOUD_ADMIN_PASSWORD=CHANGE_ME/NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD/" "$PROJECT_DIR/.env"
    
    echo -e "${GREEN}  Passwords updated${NC}"
fi

# Generate Redis session config from template (after .env is ready)
if [ -f "$PROJECT_DIR/configs/php/redis-session.ini.template" ]; then
    # Source .env to get REDIS_PASSWORD
    source "$PROJECT_DIR/.env"
    
    # Generate redis-session.ini with actual values
    sed -e "s|\${REDIS_HOST}|redis|g" \
        -e "s|\${REDIS_PORT}|6379|g" \
        -e "s|\${REDIS_PASSWORD}|${REDIS_PASSWORD:-}|g" \
        "$PROJECT_DIR/configs/php/redis-session.ini.template" > "$PROJECT_DIR/configs/php/redis-session.ini"
    echo "  Generated redis-session.ini with Redis password"
fi

echo -e "${GREEN}Environment configured${NC}"

# ==================================================
# Set Permissions
# ==================================================
echo -e "\n${YELLOW}[4/6] Checking NFS mounts...${NC}"

# Check all three NFS mounts
check_nfs_mount() {
    local mount_point="$1"
    local name="$2"
    
    if [ ! -d "$mount_point" ]; then
        echo -e "${RED}$name mount point does not exist: $mount_point${NC}"
        return 1
    fi
    
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        echo -e "${YELLOW}$name is not a mount point. Trying to mount...${NC}"
        mount -a 2>/dev/null || true
    fi
    
    if touch "$mount_point/.write_test" 2>/dev/null; then
        rm -f "$mount_point/.write_test"
        echo -e "${GREEN}  ✓ $name mount is writable${NC}"
        return 0
    else
        echo -e "${YELLOW}  ⚠ Cannot write to $name mount${NC}"
        return 1
    fi
}

NFS_CONFIG_MOUNT="${NFS_CONFIG_MOUNT:-/mnt/nextcloud/config}"
NFS_DATA_MOUNT="${NFS_DATA_MOUNT:-/mnt/nextcloud/data}"

# NOTE: PostgreSQL uses local Docker volume for better performance
# NFS is not suitable for database workloads

echo "Checking NFS mounts..."
check_nfs_mount "$NFS_CONFIG_MOUNT" "Config"
check_nfs_mount "$NFS_DATA_MOUNT" "Data"

echo -e "${GREEN}NFS mount check completed${NC}"

# ==================================================
# Pull Docker Images
# ==================================================
echo -e "\n${YELLOW}[5/6] Pulling Docker images...${NC}"

docker compose pull

# Pull NPM image if needed
if [ "${INSTALL_NPM:-false}" = "true" ]; then
    echo "Pulling Nginx Proxy Manager image..."
    docker compose -f docker-compose.yml -f docker-compose.npm.yml pull npm 2>/dev/null || true
fi

# Pull Collabora image if needed
if [ "${INSTALL_COLLABORA:-false}" = "true" ]; then
    echo "Pulling Collabora Online image..."
    docker compose -f docker-compose.yml -f docker-compose.collabora.yml pull collabora 2>/dev/null || true
fi

echo -e "${GREEN}Images pulled successfully${NC}"

# ==================================================
# Start Services
# ==================================================
echo -e "\n${YELLOW}[6/6] Starting services...${NC}"

# Start main services
docker compose up -d

# Start NPM if configured
if [ "${INSTALL_NPM:-false}" = "true" ]; then
    echo "Starting Nginx Proxy Manager..."
    if [ -f "$PROJECT_DIR/docker-compose.npm.yml" ]; then
        docker compose -f docker-compose.yml -f docker-compose.npm.yml up -d npm
        echo -e "${GREEN}NPM started on port ${NPM_ADMIN_PORT:-81}${NC}"
    fi
fi

# Start Collabora if configured
if [ "${INSTALL_COLLABORA:-false}" = "true" ]; then
    echo "Starting Collabora Online (Office Suite)..."
    if [ -f "$PROJECT_DIR/docker-compose.collabora.yml" ]; then
        docker compose -f docker-compose.yml -f docker-compose.collabora.yml up -d collabora
        echo -e "${GREEN}Collabora started on port ${COLLABORA_PORT:-9980}${NC}"
    fi
fi

echo -e "${GREEN}Services started${NC}"

# ==================================================
# Wait for Services
# ==================================================
echo -e "\n${YELLOW}Waiting for services to be ready...${NC}"

echo "Waiting for PostgreSQL..."
until docker exec postgres pg_isready -U nextcloud -d nextcloud &>/dev/null; do
    sleep 2
done
echo -e "${GREEN}PostgreSQL is ready${NC}"

echo "Waiting for Nextcloud..."
sleep 10

# Check if Nextcloud is responding
RETRY=0
MAX_RETRY=30
until curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null | grep -q "200\|302\|301"; do
    RETRY=$((RETRY + 1))
    if [ $RETRY -ge $MAX_RETRY ]; then
        echo -e "${YELLOW}Nextcloud is taking longer than expected to start.${NC}"
        echo "Check logs with: docker compose logs -f nextcloud"
        break
    fi
    echo "Waiting... ($RETRY/$MAX_RETRY)"
    sleep 5
done

# ==================================================
# Post-deployment Configuration
# ==================================================
echo -e "\n${YELLOW}Running post-deployment configuration...${NC}"

# Wait a bit more for Nextcloud to fully initialize
sleep 10

# Note: www-data user in Alpine container has UID 82
# All occ commands must run as www-data user

# Set cron mode
echo "Setting background jobs to cron..."
docker exec -u www-data nextcloud php occ background:cron 2>/dev/null || true

# Add missing indices
echo "Adding missing database indices..."
docker exec -u www-data nextcloud php occ db:add-missing-indices 2>/dev/null || true

# Convert filecache bigint
echo "Converting filecache to bigint..."
docker exec -u www-data nextcloud php occ db:convert-filecache-bigint --no-interaction 2>/dev/null || true

# Add trusted domains from configuration
echo "Configuring trusted domains..."
if [ -n "$TRUSTED_DOMAINS" ]; then
    # Parse comma-separated trusted domains
    IFS=',' read -ra DOMAINS <<< "$TRUSTED_DOMAINS"
    INDEX=0
    for DOMAIN in "${DOMAINS[@]}"; do
        DOMAIN=$(echo "$DOMAIN" | xargs)  # Trim whitespace
        docker exec -u www-data nextcloud php occ config:system:set trusted_domains $INDEX --value="$DOMAIN" 2>/dev/null || true
        echo "  Added trusted domain [$INDEX]: $DOMAIN"
        INDEX=$((INDEX + 1))
    done
fi

# Also add the server's IP if not already in trusted domains
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -n "$SERVER_IP" ] && [[ ! "$TRUSTED_DOMAINS" == *"$SERVER_IP"* ]]; then
    NEXT_INDEX=$(docker exec -u www-data nextcloud php occ config:system:get trusted_domains 2>/dev/null | wc -l)
    docker exec -u www-data nextcloud php occ config:system:set trusted_domains $NEXT_INDEX --value="$SERVER_IP" 2>/dev/null || true
    echo "  Added server IP to trusted domains: $SERVER_IP"
fi

# ==================================================
# Summary
# ==================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Deployment Complete!                 ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Services status:"
docker compose ps
echo ""
echo "Access Nextcloud:"
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ "${INSTALL_NPM:-false}" = "true" ]; then
    echo "  Internal (Nextcloud nginx): http://${SERVER_IP}:${NGINX_HTTP_PORT:-8080}"
    echo ""
    echo -e "${YELLOW}Nginx Proxy Manager:${NC}"
    echo "  Admin Panel: http://${SERVER_IP}:${NPM_ADMIN_PORT:-81}"
    echo "  Default login: admin@example.com / changeme"
    echo "  After login, add Proxy Host:"
    echo "    - Domain: your-domain.com"
    echo "    - Scheme: http"
    echo "    - Forward Hostname/IP: nginx"
    echo "    - Forward Port: 80"
    echo "    - Enable SSL with Let's Encrypt"
else
    echo "  http://${SERVER_IP}:${NGINX_HTTP_PORT:-80}"
fi

# Show Collabora info if installed
if [ "${INSTALL_COLLABORA:-false}" = "true" ]; then
    echo ""
    echo -e "${YELLOW}Collabora Online (Office Suite):${NC}"
    echo "  Internal URL: http://${SERVER_IP}:${COLLABORA_PORT:-9980}"
    echo ""
    echo "  To configure in Nextcloud:"
    echo "    1. Go to Settings → Administration → Office"
    echo "    2. Select 'Use your own server'"
    if [ "${INSTALL_NPM:-false}" = "true" ]; then
        echo "    3. Enter: https://office.${NEXTCLOUD_DOMAIN:-yourdomain.com}"
        echo ""
        echo "  Add Collabora to NPM:"
        echo "    - Domain: office.${NEXTCLOUD_DOMAIN:-yourdomain.com}"
        echo "    - Scheme: http"
        echo "    - Forward Hostname/IP: collabora"
        echo "    - Forward Port: 9980"
        echo "    - Enable SSL with Let's Encrypt"
        echo "    - Enable 'Websockets Support'"
    else
        echo "    3. Enter: http://${SERVER_IP}:${COLLABORA_PORT:-9980}"
    fi
fi
echo ""
echo "Default admin credentials are in .env file:"
echo "  cat $PROJECT_DIR/.env"
echo ""
echo "Useful commands:"
echo "  View logs:     cd $PROJECT_DIR && docker compose logs -f"
echo "  Stop:          cd $PROJECT_DIR && docker compose down"
echo "  Restart:       cd $PROJECT_DIR && docker compose restart"

# Show update command based on what's installed
UPDATE_CMD="docker compose pull && docker compose up -d"
if [ "${INSTALL_NPM:-false}" = "true" ] && [ "${INSTALL_COLLABORA:-false}" = "true" ]; then
    UPDATE_CMD="docker compose -f docker-compose.yml -f docker-compose.npm.yml -f docker-compose.collabora.yml pull && docker compose -f docker-compose.yml -f docker-compose.npm.yml -f docker-compose.collabora.yml up -d"
elif [ "${INSTALL_NPM:-false}" = "true" ]; then
    UPDATE_CMD="docker compose -f docker-compose.yml -f docker-compose.npm.yml pull && docker compose -f docker-compose.yml -f docker-compose.npm.yml up -d"
elif [ "${INSTALL_COLLABORA:-false}" = "true" ]; then
    UPDATE_CMD="docker compose -f docker-compose.yml -f docker-compose.collabora.yml pull && docker compose -f docker-compose.yml -f docker-compose.collabora.yml up -d"
fi
echo "  Update:       cd $PROJECT_DIR && $UPDATE_CMD"

if [ "${INSTALL_NPM:-false}" != "true" ]; then
echo ""
echo -e "${YELLOW}For external access with SSL:${NC}"
echo "  Use Nginx Proxy Manager or similar reverse proxy"
echo "  Point it to this server's IP on port ${NGINX_HTTP_PORT:-80}"
fi
