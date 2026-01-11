#!/bin/bash
# ==================================================
# Nextcloud Uninstall / Cleanup Script
# ==================================================
# This script removes the Nextcloud installation
# WARNING: This can delete your data!
# Run as: sudo ./uninstall.sh
# ==================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_DIR/.install-config"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Defaults
PROJECT_DIR="${PROJECT_DIR:-/opt/nextcloud}"
NFS_BASE_MOUNT="${NFS_BASE_MOUNT:-/mnt/nextcloud}"
NFS_CONFIG_MOUNT="${NFS_CONFIG_MOUNT:-$NFS_BASE_MOUNT/config}"
NFS_DATA_MOUNT="${NFS_DATA_MOUNT:-$NFS_BASE_MOUNT/data}"
NFS_DATABASE_MOUNT="${NFS_DATABASE_MOUNT:-$NFS_BASE_MOUNT/database}"

print_banner() {
    clear
    echo -e "${RED}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║            NEXTCLOUD UNINSTALL / CLEANUP SCRIPT               ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

print_banner

echo -e "${BOLD}Bu script asagidaki islemleri yapabilir:${NC}"
echo ""
echo "  1) Sadece Docker container'larini durdur"
echo "  2) Container ve volume'lari sil (veriler korunur)"
echo "  3) Tam temizlik - Docker + NFS mount'lari kaldir"
echo "  4) TAM SILME - Her seyi sil (VERILER DAHIL!)"
echo "  5) Iptal"
echo ""
echo -e "${YELLOW}Mevcut Yapilandirma:${NC}"
echo "  Proje Dizini : $PROJECT_DIR"
echo "  Config Mount : $NFS_CONFIG_MOUNT"
echo "  Data Mount   : $NFS_DATA_MOUNT"
echo "  DB Mount     : $NFS_DATABASE_MOUNT"
echo ""

read -p "Seciminiz [1-5]: " choice

case $choice in
    1)
        # ==================================================
        # Option 1: Just stop containers
        # ==================================================
        echo ""
        print_info "Container'lar durduruluyor..."
        
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR"
            if [ -f "docker-compose.yml" ]; then
                docker compose down 2>/dev/null || true
                print_success "Container'lar durduruldu"
            else
                print_warning "docker-compose.yml bulunamadi"
            fi
        else
            # Try to stop by container names
            docker stop nextcloud nginx postgres redis nextcloud-cron nginx-proxy-manager 2>/dev/null || true
            print_success "Container'lar durduruldu"
        fi
        
        echo ""
        print_success "Islem tamamlandi. Container'lar durduruldu."
        print_info "Yeniden baslatmak icin: cd $PROJECT_DIR && docker compose up -d"
        ;;
        
    2)
        # ==================================================
        # Option 2: Remove containers and volumes (keep data)
        # ==================================================
        echo ""
        print_warning "Container ve Docker volume'lari silinecek."
        print_info "NFS mount'larindaki verileriniz korunacak."
        echo ""
        read -p "Devam etmek istiyor musunuz? (y/n): " confirm
        
        if [ "$confirm" != "y" ]; then
            print_info "Iptal edildi."
            exit 0
        fi
        
        echo ""
        print_info "Container'lar kaldiriliyor..."
        
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR"
            if [ -f "docker-compose.yml" ]; then
                docker compose down -v 2>/dev/null || true
            fi
        fi
        
        # Remove by name if compose didn't work
        docker rm -f nextcloud nginx postgres redis nextcloud-cron nginx-proxy-manager 2>/dev/null || true
        
        # Remove volumes
        docker volume rm nextcloud-app npm-data npm-letsencrypt 2>/dev/null || true
        
        print_success "Container ve volume'lar silindi"
        
        # Remove project directory (but not NFS data)
        if [ -d "$PROJECT_DIR" ]; then
            echo ""
            read -p "$PROJECT_DIR dizini silinsin mi? (y/n): " del_project
            if [ "$del_project" = "y" ]; then
                rm -rf "$PROJECT_DIR"
                print_success "Proje dizini silindi"
            fi
        fi
        
        echo ""
        print_success "Islem tamamlandi."
        print_info "NFS mount'larindaki verileriniz korundu."
        ;;
        
    3)
        # ==================================================
        # Option 3: Full cleanup (Docker + NFS mounts)
        # ==================================================
        echo ""
        print_warning "Docker container'lari ve NFS mount'lari kaldirilacak."
        print_info "TrueNAS'taki verileriniz korunacak."
        echo ""
        read -p "Devam etmek istiyor musunuz? (y/n): " confirm
        
        if [ "$confirm" != "y" ]; then
            print_info "Iptal edildi."
            exit 0
        fi
        
        echo ""
        
        # Stop containers
        print_info "Container'lar durduruluyor..."
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR" 2>/dev/null
            docker compose down -v 2>/dev/null || true
        fi
        docker rm -f nextcloud nginx postgres redis nextcloud-cron nginx-proxy-manager 2>/dev/null || true
        docker volume rm nextcloud-app npm-data npm-letsencrypt 2>/dev/null || true
        print_success "Container'lar kaldirildi"
        
        # Unmount NFS
        print_info "NFS mount'lari kaldiriliyor..."
        umount "$NFS_CONFIG_MOUNT" 2>/dev/null || true
        umount "$NFS_DATA_MOUNT" 2>/dev/null || true
        umount "$NFS_DATABASE_MOUNT" 2>/dev/null || true
        print_success "NFS mount'lari kaldirildi"
        
        # Remove from fstab
        print_info "fstab'dan girisler kaldiriliyor..."
        cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
        sed -i '/# Nextcloud/d' /etc/fstab 2>/dev/null || true
        sed -i '/nextcloud/d' /etc/fstab 2>/dev/null || true
        print_success "fstab guncellendi"
        
        # Remove mount directories
        rmdir "$NFS_CONFIG_MOUNT" 2>/dev/null || true
        rmdir "$NFS_DATA_MOUNT" 2>/dev/null || true
        rmdir "$NFS_DATABASE_MOUNT" 2>/dev/null || true
        rmdir "$NFS_BASE_MOUNT" 2>/dev/null || true
        
        # Remove project directory
        if [ -d "$PROJECT_DIR" ]; then
            rm -rf "$PROJECT_DIR"
            print_success "Proje dizini silindi: $PROJECT_DIR"
        fi
        
        # Remove config files
        rm -f "$REPO_DIR/.install-config" 2>/dev/null || true
        rm -f "$REPO_DIR/docker/.env" 2>/dev/null || true
        rm -f "$REPO_DIR/docker/docker-compose.override.yml" 2>/dev/null || true
        print_success "Yapilandirma dosyalari silindi"
        
        echo ""
        print_success "Temizlik tamamlandi!"
        print_info "TrueNAS'taki verileriniz korundu."
        print_info "Yeniden kurulum icin: ./setup.sh"
        ;;
        
    4)
        # ==================================================
        # Option 4: COMPLETE REMOVAL (INCLUDING DATA!)
        # ==================================================
        echo ""
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                         DIKKAT!                               ║${NC}"
        echo -e "${RED}║                                                               ║${NC}"
        echo -e "${RED}║  Bu islem TUM VERILERINIZI SILECEK!                           ║${NC}"
        echo -e "${RED}║  - Nextcloud yapilandirmasi                                   ║${NC}"
        echo -e "${RED}║  - Veritabani                                                 ║${NC}"
        echo -e "${RED}║  - Kullanici dosyalari (60TB data!)                           ║${NC}"
        echo -e "${RED}║                                                               ║${NC}"
        echo -e "${RED}║  BU ISLEM GERI ALINAMAZ!                                      ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Generate random 6-digit code for confirmation
        CONFIRM_CODE=$(shuf -i 100000-999999 -n 1)
        echo -e "${YELLOW}Onay kodu: ${BOLD}$CONFIRM_CODE${NC}"
        echo ""
        read -p "Devam etmek icin yukaridaki 6 haneli kodu girin: " user_code
        
        if [ "$user_code" != "$CONFIRM_CODE" ]; then
            print_info "Kod eslesmedi. Islem iptal edildi."
            exit 0
        fi
        
        echo ""
        read -p "Son onay - 'DELETE' yazin: " confirm2
        
        if [ "$confirm2" != "DELETE" ]; then
            print_info "Iptal edildi."
            exit 0
        fi
        
        echo ""
        print_error "TUM VERILER SILINIYOR..."
        
        # Stop and remove containers
        print_info "Container'lar kaldiriliyor..."
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR" 2>/dev/null
            docker compose down -v 2>/dev/null || true
        fi
        docker rm -f nextcloud nginx postgres redis nextcloud-cron nginx-proxy-manager 2>/dev/null || true
        docker volume rm nextcloud-app npm-data npm-letsencrypt 2>/dev/null || true
        
        # Delete data on NFS mounts
        print_error "NFS mount'larindaki veriler siliniyor..."
        
        if mountpoint -q "$NFS_CONFIG_MOUNT" 2>/dev/null; then
            rm -rf "$NFS_CONFIG_MOUNT"/* 2>/dev/null || true
            print_error "  Config verileri silindi"
        fi
        
        if mountpoint -q "$NFS_DATA_MOUNT" 2>/dev/null; then
            rm -rf "$NFS_DATA_MOUNT"/* 2>/dev/null || true
            print_error "  Data verileri silindi"
        fi
        
        if mountpoint -q "$NFS_DATABASE_MOUNT" 2>/dev/null; then
            rm -rf "$NFS_DATABASE_MOUNT"/* 2>/dev/null || true
            print_error "  Database verileri silindi"
        fi
        
        # Unmount NFS
        umount "$NFS_CONFIG_MOUNT" 2>/dev/null || true
        umount "$NFS_DATA_MOUNT" 2>/dev/null || true
        umount "$NFS_DATABASE_MOUNT" 2>/dev/null || true
        
        # Remove from fstab
        cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
        sed -i '/# Nextcloud/d' /etc/fstab 2>/dev/null || true
        sed -i '/nextcloud/d' /etc/fstab 2>/dev/null || true
        
        # Remove directories
        rmdir "$NFS_CONFIG_MOUNT" 2>/dev/null || true
        rmdir "$NFS_DATA_MOUNT" 2>/dev/null || true
        rmdir "$NFS_DATABASE_MOUNT" 2>/dev/null || true
        rmdir "$NFS_BASE_MOUNT" 2>/dev/null || true
        
        # Remove project directory
        rm -rf "$PROJECT_DIR" 2>/dev/null || true
        
        # Remove config files
        rm -f "$REPO_DIR/.install-config" 2>/dev/null || true
        rm -f "$REPO_DIR/docker/.env" 2>/dev/null || true
        rm -f "$REPO_DIR/docker/docker-compose.override.yml" 2>/dev/null || true
        
        echo ""
        print_error "TUM VERILER SILINDI!"
        echo ""
        print_info "TrueNAS'taki dataset'leri de silmek icin:"
        echo "  TrueNAS arayuzunden: Storage > Pools > nextcloud dataset > Delete"
        ;;
        
    5)
        print_info "Iptal edildi."
        exit 0
        ;;
        
    *)
        print_error "Gecersiz secim!"
        exit 1
        ;;
esac

echo ""
