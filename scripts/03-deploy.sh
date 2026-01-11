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
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-/opt/nextcloud}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Nextcloud Deployment Script          ${NC}"
echo -e "${GREEN}========================================${NC}"

# ==================================================
# Pre-flight Checks
# ==================================================
echo -e "\n${YELLOW}[1/7] Running pre-flight checks...${NC}"

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
if ! mountpoint -q /mnt/nextcloud-data; then
    echo -e "${RED}NFS data mount is not available. Run 02-mount-nfs.sh first.${NC}"
    exit 1
fi

if ! mountpoint -q /mnt/nextcloud-config; then
    echo -e "${RED}NFS config mount is not available. Run 02-mount-nfs.sh first.${NC}"
    exit 1
fi

echo -e "${GREEN}All pre-flight checks passed!${NC}"

# ==================================================
# Copy Docker Files to Project Directory
# ==================================================
echo -e "\n${YELLOW}[2/8] Copying Docker files to $PROJECT_DIR...${NC}"

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

# Copy configs directory
mkdir -p "$PROJECT_DIR/configs"
cp -r "$DOCKER_DIR/configs/"* "$PROJECT_DIR/configs/" 2>/dev/null || true
echo "  Copied configs/"

# Create necessary directories
mkdir -p "$PROJECT_DIR/db-data"
mkdir -p "$PROJECT_DIR/redis-data"
mkdir -p "$PROJECT_DIR/ssl"

echo -e "${GREEN}Docker files copied${NC}"

# ==================================================
# Configure Environment
# ==================================================
echo -e "\n${YELLOW}[3/8] Configuring environment...${NC}"

cd "$PROJECT_DIR"

# Create .env if it doesn't exist
if [ ! -f ".env" ]; then
    if [ -f "$DOCKER_DIR/.env.example" ]; then
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
        echo -e "${RED}.env.example not found${NC}"
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
echo -e "\n${YELLOW}[4/8] Setting permissions...${NC}"

# www-data UID:GID is typically 33:33
WWW_DATA_UID=33
WWW_DATA_GID=33

# NFS mounts: ownership must be set on TrueNAS, not here
# Check if we can write to NFS mounts
NFS_PERMISSION_OK=true

if ! sudo -u \#${WWW_DATA_UID} touch /mnt/nextcloud-data/.write_test 2>/dev/null; then
    NFS_PERMISSION_OK=false
    echo -e "${YELLOW}WARNING: Cannot write to /mnt/nextcloud-data as www-data (UID 33)${NC}"
else
    rm -f /mnt/nextcloud-data/.write_test
    echo "  NFS data mount: writable"
fi

if ! sudo -u \#${WWW_DATA_UID} touch /mnt/nextcloud-config/.write_test 2>/dev/null; then
    NFS_PERMISSION_OK=false
    echo -e "${YELLOW}WARNING: Cannot write to /mnt/nextcloud-config as www-data (UID 33)${NC}"
else
    rm -f /mnt/nextcloud-config/.write_test
    echo "  NFS config mount: writable"
fi

if [ "$NFS_PERMISSION_OK" = false ]; then
    echo ""
    echo -e "${YELLOW}NFS permissions need to be set on TrueNAS:${NC}"
    echo "  1. Open TrueNAS Web UI"
    echo "  2. Go to Datasets > nextcloud/data > Edit Permissions"
    echo "  3. Set User: 33, Group: 33 (or create www-data user with UID 33)"
    echo "  4. Apply recursively"
    echo "  5. Do the same for nextcloud/config dataset"
    echo ""
    echo -e "${YELLOW}Or run these commands on TrueNAS shell:${NC}"
    echo "  chown -R 33:33 /mnt/storage/nextcloud/data"
    echo "  chown -R 33:33 /mnt/storage/nextcloud/config"
    echo ""
    read -p "Press Enter after fixing TrueNAS permissions (or Ctrl+C to exit)..."
    
    # Re-check after user confirmation
    if ! sudo -u \#${WWW_DATA_UID} touch /mnt/nextcloud-data/.write_test 2>/dev/null; then
        echo -e "${RED}Still cannot write to NFS mounts. Please fix permissions and try again.${NC}"
        exit 1
    fi
    rm -f /mnt/nextcloud-data/.write_test
fi

# Set ownership on local directories
chown -R $WWW_DATA_UID:$WWW_DATA_GID db-data 2>/dev/null || true
chown -R $WWW_DATA_UID:$WWW_DATA_GID redis-data 2>/dev/null || true

echo -e "${GREEN}Permissions set${NC}"

# ==================================================
# Create SSL Certificates (Self-signed for initial setup)
# ==================================================
echo -e "\n${YELLOW}[5/8] Checking SSL certificates...${NC}"

if [ ! -f "ssl/fullchain.pem" ] || [ ! -f "ssl/privkey.pem" ]; then
    echo "Creating self-signed certificates for initial setup..."
    
    mkdir -p ssl
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout ssl/privkey.pem \
        -out ssl/fullchain.pem \
        -subj "/C=TR/ST=Istanbul/L=Istanbul/O=Nextcloud/CN=localhost"
    
    echo -e "${YELLOW}Self-signed certificates created.${NC}"
    echo "For production, replace with Let's Encrypt certificates."
else
    echo -e "${GREEN}SSL certificates found${NC}"
fi

# ==================================================
# Pull Docker Images
# ==================================================
echo -e "\n${YELLOW}[6/8] Pulling Docker images...${NC}"

docker compose pull

echo -e "${GREEN}Images pulled successfully${NC}"

# ==================================================
# Start Services
# ==================================================
echo -e "\n${YELLOW}[7/8] Starting services...${NC}"

docker compose up -d

echo -e "${GREEN}Services started${NC}"

# ==================================================
# Wait for Services
# ==================================================
echo -e "\n${YELLOW}[8/8] Waiting for services to be ready...${NC}"

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

# Set cron mode
docker exec -u www-data nextcloud php occ background:cron 2>/dev/null || true

# Add missing indices
docker exec -u www-data nextcloud php occ db:add-missing-indices 2>/dev/null || true

# Convert filecache bigint
docker exec -u www-data nextcloud php occ db:convert-filecache-bigint --no-interaction 2>/dev/null || true

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
echo "  Local:  https://localhost"
echo "  Remote: https://your-domain.com"
echo ""
echo "Default admin credentials are in .env file"
echo ""
echo "Useful commands:"
echo "  View logs:     docker compose logs -f"
echo "  Stop:          docker compose down"
echo "  Restart:       docker compose restart"
echo "  Update:        docker compose pull && docker compose up -d"
echo ""
echo -e "${YELLOW}IMPORTANT: For production, get proper SSL certificates:${NC}"
echo "  sudo certbot certonly --standalone -d your-domain.com"
echo "  cp /etc/letsencrypt/live/your-domain.com/*.pem ssl/"
echo "  docker compose restart nginx"
