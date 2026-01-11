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
# Check Project Directory
# ==================================================
echo -e "\n${YELLOW}[2/7] Checking project directory...${NC}"

cd $PROJECT_DIR

if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}docker-compose.yml not found in $PROJECT_DIR${NC}"
    echo "Please copy the docker files first."
    exit 1
fi

if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo -e "${YELLOW}Creating .env from .env.example...${NC}"
        cp .env.example .env
        echo -e "${RED}Please edit .env file with your settings and run again.${NC}"
        echo "  nano $PROJECT_DIR/.env"
        exit 1
    else
        echo -e "${RED}.env file not found${NC}"
        exit 1
    fi
fi

# Check for default passwords
if grep -q "CHANGE_ME" .env; then
    echo -e "${RED}Please update the passwords in .env file!${NC}"
    echo "Found 'CHANGE_ME' placeholder. Edit the file:"
    echo "  nano $PROJECT_DIR/.env"
    exit 1
fi

echo -e "${GREEN}Project directory ready${NC}"

# ==================================================
# Set Permissions
# ==================================================
echo -e "\n${YELLOW}[3/7] Setting permissions...${NC}"

# www-data UID:GID is typically 33:33
WWW_DATA_UID=33
WWW_DATA_GID=33

# Set ownership on NFS mounts (should match TrueNAS settings)
sudo chown -R $WWW_DATA_UID:$WWW_DATA_GID /mnt/nextcloud-data
sudo chown -R $WWW_DATA_UID:$WWW_DATA_GID /mnt/nextcloud-config
sudo chmod -R 770 /mnt/nextcloud-data
sudo chmod -R 770 /mnt/nextcloud-config

# Set ownership on local directories
sudo chown -R $WWW_DATA_UID:$WWW_DATA_GID db-data 2>/dev/null || true
sudo chown -R $WWW_DATA_UID:$WWW_DATA_GID redis-data 2>/dev/null || true

echo -e "${GREEN}Permissions set${NC}"

# ==================================================
# Create SSL Certificates (Self-signed for initial setup)
# ==================================================
echo -e "\n${YELLOW}[4/7] Checking SSL certificates...${NC}"

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
echo -e "\n${YELLOW}[5/7] Pulling Docker images...${NC}"

docker compose pull

echo -e "${GREEN}Images pulled successfully${NC}"

# ==================================================
# Start Services
# ==================================================
echo -e "\n${YELLOW}[6/7] Starting services...${NC}"

docker compose up -d

echo -e "${GREEN}Services started${NC}"

# ==================================================
# Wait for Services
# ==================================================
echo -e "\n${YELLOW}[7/7] Waiting for services to be ready...${NC}"

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
