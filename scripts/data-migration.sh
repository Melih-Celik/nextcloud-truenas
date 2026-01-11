#!/bin/bash
# ==================================================
# Nextcloud Veri Aktarım Scripti
# ==================================================
# Bu script büyük miktarda veriyi Nextcloud'a aktarır
# ve dosya veritabanını günceller.
#
# Kullanım: sudo ./data-migration.sh
# ==================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_DIR/.install-config"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Defaults
NFS_DATA_MOUNT="${NFS_DATA_MOUNT:-/mnt/nextcloud-data}"
PROJECT_DIR="${PROJECT_DIR:-/opt/nextcloud}"

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     📦 Nextcloud Veri Aktarım Aracı                          ║${NC}"
echo -e "${CYAN}║     60TB+ Veri Migrasyon Scripti                             ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ==================================================
# Functions
# ==================================================

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

show_help() {
    echo "Kullanım: $0 [SEÇENEK]"
    echo ""
    echo "Seçenekler:"
    echo "  --scan              Nextcloud dosya veritabanını tara (tüm kullanıcılar)"
    echo "  --scan-user USER    Belirli kullanıcının dosyalarını tara"
    echo "  --import-dir DIR    Dizini belirli kullanıcıya aktar"
    echo "  --status            Mevcut durumu göster"
    echo "  --help              Bu yardım mesajını göster"
    echo ""
    echo "Veri Aktarım Yöntemleri:"
    echo ""
    echo "  1. DOĞRUDAN NFS KOPYALAMA (Önerilen - En Hızlı)"
    echo "     Veriyi doğrudan TrueNAS NFS paylaşımına kopyalayın,"
    echo "     ardından --scan ile veritabanını güncelleyin."
    echo ""
    echo "  2. RSYNC İLE KOPYALAMA"
    echo "     rsync -avP /kaynak/ $NFS_DATA_MOUNT/USERNAME/files/"
    echo "     ./data-migration.sh --scan-user USERNAME"
    echo ""
    echo "  3. NEXTCLOUD CLI"
    echo "     docker exec -u www-data nextcloud php occ files:scan --all"
}

check_nextcloud() {
    if ! docker ps | grep -q "nextcloud"; then
        echo -e "${RED}Hata: Nextcloud container çalışmıyor!${NC}"
        exit 1
    fi
}

get_users() {
    docker exec -u www-data nextcloud php occ user:list --output=json 2>/dev/null | grep -oP '"\K[^"]+(?=":)' || true
}

scan_all_users() {
    print_section "📂 Tüm Kullanıcılar İçin Dosya Taraması"
    
    echo -e "${YELLOW}Bu işlem büyük veri setleri için uzun sürebilir...${NC}"
    echo ""
    
    # Maintenance mode
    echo "Maintenance mode aktif ediliyor..."
    docker exec -u www-data nextcloud php occ maintenance:mode --on
    
    # Full scan
    echo ""
    echo "Dosya taraması başlıyor..."
    docker exec -u www-data nextcloud php occ files:scan --all -v
    
    # Cleanup
    echo ""
    echo "Önbellek temizleniyor..."
    docker exec -u www-data nextcloud php occ files:cleanup
    
    # Maintenance mode off
    echo ""
    echo "Maintenance mode kapatılıyor..."
    docker exec -u www-data nextcloud php occ maintenance:mode --off
    
    echo ""
    echo -e "${GREEN}✓ Dosya taraması tamamlandı!${NC}"
}

scan_user() {
    local user="$1"
    
    print_section "📂 Kullanıcı Dosya Taraması: $user"
    
    echo "Kullanıcı dosyaları taranıyor: $user"
    docker exec -u www-data nextcloud php occ files:scan "$user" -v
    
    echo ""
    echo -e "${GREEN}✓ $user kullanıcısının dosyaları tarandı!${NC}"
}

import_directory() {
    local source_dir="$1"
    local target_user="$2"
    
    if [ -z "$source_dir" ] || [ -z "$target_user" ]; then
        echo -e "${RED}Hata: Kaynak dizin ve hedef kullanıcı belirtilmeli!${NC}"
        echo "Kullanım: $0 --import-dir /kaynak/dizin --user kullanici_adi"
        exit 1
    fi
    
    print_section "📦 Dizin İçe Aktarma"
    
    local target_dir="$NFS_DATA_MOUNT/$target_user/files"
    
    # Check source
    if [ ! -d "$source_dir" ]; then
        echo -e "${RED}Hata: Kaynak dizin bulunamadı: $source_dir${NC}"
        exit 1
    fi
    
    # Check target user exists
    if ! docker exec -u www-data nextcloud php occ user:info "$target_user" &>/dev/null; then
        echo -e "${RED}Hata: Kullanıcı bulunamadı: $target_user${NC}"
        echo "Önce kullanıcıyı oluşturun:"
        echo "  docker exec -u www-data nextcloud php occ user:add $target_user"
        exit 1
    fi
    
    # Create target directory
    mkdir -p "$target_dir"
    
    echo "Kaynak: $source_dir"
    echo "Hedef:  $target_dir"
    echo ""
    
    # Calculate size
    echo "Kaynak boyutu hesaplanıyor..."
    local size=$(du -sh "$source_dir" 2>/dev/null | cut -f1)
    echo "Toplam boyut: $size"
    echo ""
    
    # Confirm
    read -p "Kopyalamaya başlansın mı? [e/H]: " confirm
    if [[ ! "$confirm" =~ ^[eEyY]$ ]]; then
        echo "İptal edildi."
        exit 0
    fi
    
    # Copy with rsync
    echo ""
    echo "Kopyalama başlıyor (rsync)..."
    rsync -avP --info=progress2 "$source_dir/" "$target_dir/"
    
    # Fix permissions
    echo ""
    echo "İzinler düzenleniyor..."
    chown -R 82:82 "$target_dir"
    
    # Scan
    echo ""
    echo "Nextcloud veritabanı güncelleniyor..."
    docker exec -u www-data nextcloud php occ files:scan "$target_user" -v
    
    echo ""
    echo -e "${GREEN}✓ Veri aktarımı tamamlandı!${NC}"
}

show_status() {
    print_section "📊 Nextcloud Durumu"
    
    # Disk usage
    echo -e "${YELLOW}Disk Kullanımı:${NC}"
    df -h "$NFS_DATA_MOUNT"
    echo ""
    
    # Users
    echo -e "${YELLOW}Kullanıcılar:${NC}"
    docker exec -u www-data nextcloud php occ user:list
    echo ""
    
    # Data directory size
    echo -e "${YELLOW}Veri Dizini Boyutu:${NC}"
    du -sh "$NFS_DATA_MOUNT"/* 2>/dev/null | head -20
    echo ""
    
    # Nextcloud status
    echo -e "${YELLOW}Nextcloud Durumu:${NC}"
    docker exec -u www-data nextcloud php occ status
}

# ==================================================
# Main
# ==================================================

check_nextcloud

case "${1:-}" in
    --scan)
        scan_all_users
        ;;
    --scan-user)
        if [ -z "$2" ]; then
            echo -e "${RED}Hata: Kullanıcı adı belirtilmeli!${NC}"
            exit 1
        fi
        scan_user "$2"
        ;;
    --import-dir)
        import_directory "$2" "$4"
        ;;
    --status)
        show_status
        ;;
    --help|-h|"")
        show_help
        ;;
    *)
        echo -e "${RED}Bilinmeyen seçenek: $1${NC}"
        show_help
        exit 1
        ;;
esac
