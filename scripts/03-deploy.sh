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

# Copy override file if exists
if [ -f "$DOCKER_DIR/docker-compose.override.yml" ]; then
    cp "$DOCKER_DIR/docker-compose.override.yml" "$PROJECT_DIR/"
    echo "  Copied docker-compose.override.yml"
fi

# Copy configs directory
mkdir -p "$PROJECT_DIR/configs"
cp -r "$DOCKER_DIR/configs/"* "$PROJECT_DIR/configs/" 2>/dev/null || true
echo "  Copied configs/"

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

echo -e "${GREEN}Environment configured${NC}"

# ==================================================
# Set Permissions
# ==================================================
echo -e "\n${YELLOW}[4/6] Checking NFS mount...${NC}"

# Test if we can write to NFS mount at all
if touch "$NFS_DATA_MOUNT/.write_test" 2>/dev/null; then
    rm -f "$NFS_DATA_MOUNT/.write_test"
    echo -e "${GREEN}NFS data mount is writable${NC}"
else
    echo -e "${RED}Cannot write to NFS mount at all!${NC}"
    echo "Check TrueNAS NFS share permissions."
    exit 1
fi

echo -e "${GREEN}NFS mount check passed${NC}"

# ==================================================
# Pull Docker Images
# ==================================================
echo -e "\n${YELLOW}[5/6] Pulling Docker images...${NC}"

docker compose pull

echo -e "${GREEN}Images pulled successfully${NC}"

# ==================================================
# Start Services
# ==================================================
echo -e "\n${YELLOW}[6/6] Starting services...${NC}"

docker compose up -d

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
sleep 5

# Set cron mode (run as the nextcloud user inside container)
docker exec nextcloud php occ background:cron 2>/dev/null || true

# Add missing indices
docker exec nextcloud php occ db:add-missing-indices 2>/dev/null || true

# Convert filecache bigint
docker exec nextcloud php occ db:convert-filecache-bigint --no-interaction 2>/dev/null || true

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
echo "  http://$(hostname -I | awk '{print $1}')"
echo ""
echo "Default admin credentials are in .env file:"
echo "  cat $PROJECT_DIR/.env"
echo ""
echo "Useful commands:"
echo "  View logs:     cd $PROJECT_DIR && docker compose logs -f"
echo "  Stop:          cd $PROJECT_DIR && docker compose down"
echo "  Restart:       cd $PROJECT_DIR && docker compose restart"
echo "  Update:        cd $PROJECT_DIR && docker compose pull && docker compose up -d"
echo ""
echo -e "${YELLOW}For external access with SSL:${NC}"
echo "  Use Nginx Proxy Manager or similar reverse proxy"
echo "  Point it to this server's IP on port 80"
