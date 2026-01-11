#!/bin/bash
# ==================================================
# 60TB+ Large Dataset Optimization Script
# ==================================================
# This script optimizes Nextcloud for very large datasets
# Features:
#   - Optimized file scanning (incremental)
#   - Database optimization
#   - Cache tuning
#   - Index management
# Run as: ./optimize-large-data.sh
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_DIR/.install-config"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

PROJECT_DIR="${PROJECT_DIR:-/opt/nextcloud}"
INDEX_WORKERS="${INDEX_WORKERS:-4}"
SCAN_BATCH_SIZE="${SCAN_BATCH_SIZE:-1000}"

print_header() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     60TB+ Büyük Veri Seti Optimizasyon Aracı                  ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

run_occ() {
    docker exec -u www-data nextcloud php occ "$@"
}

show_menu() {
    print_header
    echo ""
    echo "Seçenekler:"
    echo ""
    echo "  1) Dosya Tarama (files:scan)"
    echo "     - Tek kullanıcı tarama"
    echo "     - Tüm kullanıcıları tarama"
    echo "     - Sadece değişiklikleri tarama (hızlı)"
    echo ""
    echo "  2) Veritabanı Optimizasyonu"
    echo "     - Eksik indeksleri ekle"
    echo "     - BigInt dönüşümü"
    echo "     - VACUUM/ANALYZE"
    echo ""
    echo "  3) Önbellek Yönetimi"
    echo "     - Redis istatistikleri"
    echo "     - Önbellek temizle"
    echo "     - APCu durumu"
    echo ""
    echo "  4) Dosya Yönetimi"
    echo "     - Toplam dosya sayısı"
    echo "     - Kullanıcı kotaları"
    echo "     - Çöp kutusu temizliği"
    echo ""
    echo "  5) Performans Raporu"
    echo ""
    echo "  6) Tam Optimizasyon (Tümünü çalıştır)"
    echo ""
    echo "  7) Arkaplan Görevleri Durumu"
    echo ""
    echo "  0) Çıkış"
    echo ""
    read -p "Seçiminiz [0-7]: " choice
}

# ==================================================
# File Scanning Functions
# ==================================================
scan_files_menu() {
    print_section "📁 Dosya Tarama"
    
    echo "Dosya tarama seçenekleri:"
    echo ""
    echo "  1) Tüm kullanıcıları tara (yavaş, ilk kurulum için)"
    echo "  2) Tek kullanıcı tara"
    echo "  3) Sadece değişiklikleri tara (hızlı, günlük kullanım)"
    echo "  4) Belirli bir dizini tara"
    echo "  5) Tarama durumunu kontrol et"
    echo "  6) Geri"
    echo ""
    read -p "Seçiminiz [1-6]: " scan_choice
    
    case $scan_choice in
        1)
            echo ""
            echo -e "${YELLOW}⚠ 60TB veri için bu işlem SAATLER sürebilir!${NC}"
            echo "Önerilen: nohup kullanarak arkaplanda çalıştırın"
            echo ""
            read -p "Devam? (e/h): " confirm
            if [ "$confirm" = "e" ]; then
                echo "Tüm dosyalar taranıyor..."
                run_occ files:scan --all -v
            fi
            ;;
        2)
            echo ""
            echo "Mevcut kullanıcılar:"
            run_occ user:list
            echo ""
            read -p "Kullanıcı adı: " username
            if [ -n "$username" ]; then
                echo "Kullanıcı dosyaları taranıyor: $username"
                run_occ files:scan "$username" -v
            fi
            ;;
        3)
            echo "Değişiklikler taranıyor (incremental)..."
            run_occ files:scan --all --shallow -v
            ;;
        4)
            read -p "Dizin yolu (örn: /admin/files/Documents): " path
            if [ -n "$path" ]; then
                echo "Dizin taranıyor: $path"
                run_occ files:scan --path="$path" -v
            fi
            ;;
        5)
            echo ""
            echo "Tarama durumu kontrol ediliyor..."
            # Check if scan is running
            if docker exec nextcloud pgrep -f "files:scan" >/dev/null 2>&1; then
                echo -e "${YELLOW}Tarama işlemi devam ediyor...${NC}"
            else
                echo -e "${GREEN}Aktif tarama yok${NC}"
            fi
            ;;
        6)
            return
            ;;
    esac
}

# ==================================================
# Database Optimization
# ==================================================
optimize_database() {
    print_section "🗄️ Veritabanı Optimizasyonu"
    
    echo "1. Eksik indeksler kontrol ediliyor..."
    run_occ db:add-missing-indices
    echo -e "${GREEN}✓ İndeksler eklendi${NC}"
    
    echo ""
    echo "2. Eksik kolonlar kontrol ediliyor..."
    run_occ db:add-missing-columns 2>/dev/null || true
    echo -e "${GREEN}✓ Kolonlar kontrol edildi${NC}"
    
    echo ""
    echo "3. BigInt dönüşümü kontrol ediliyor..."
    echo -e "${YELLOW}Not: Bu işlem uzun sürebilir ve kesinti gerektirir${NC}"
    read -p "BigInt dönüşümü yapılsın mı? (e/h): " do_bigint
    if [ "$do_bigint" = "e" ]; then
        run_occ db:convert-filecache-bigint --no-interaction
        echo -e "${GREEN}✓ BigInt dönüşümü tamamlandı${NC}"
    fi
    
    echo ""
    echo "4. PostgreSQL VACUUM/ANALYZE..."
    docker exec postgres psql -U nextcloud -d nextcloud -c "VACUUM ANALYZE;" 2>/dev/null || true
    echo -e "${GREEN}✓ VACUUM/ANALYZE tamamlandı${NC}"
    
    echo ""
    echo "5. Veritabanı istatistikleri:"
    docker exec postgres psql -U nextcloud -d nextcloud -c "
        SELECT 
            relname as table_name,
            pg_size_pretty(pg_total_relation_size(relid)) as total_size,
            n_live_tup as row_count
        FROM pg_stat_user_tables 
        ORDER BY pg_total_relation_size(relid) DESC 
        LIMIT 10;
    " 2>/dev/null || echo "İstatistikler alınamadı"
}

# ==================================================
# Cache Management
# ==================================================
manage_cache() {
    print_section "💾 Önbellek Yönetimi"
    
    echo "1. Redis İstatistikleri:"
    echo ""
    docker exec redis redis-cli INFO memory 2>/dev/null | grep -E "used_memory_human|maxmemory_human" || echo "Redis bilgisi alınamadı"
    echo ""
    docker exec redis redis-cli INFO stats 2>/dev/null | grep -E "keyspace_hits|keyspace_misses" || true
    
    echo ""
    echo "2. Redis anahtar sayısı:"
    docker exec redis redis-cli DBSIZE 2>/dev/null || echo "Bilgi alınamadı"
    
    echo ""
    read -p "Redis önbelleğini temizle? (e/h): " clear_redis
    if [ "$clear_redis" = "e" ]; then
        echo "Redis temizleniyor..."
        docker exec redis redis-cli FLUSHALL 2>/dev/null || true
        echo -e "${GREEN}✓ Redis temizlendi${NC}"
    fi
    
    echo ""
    echo "3. Nextcloud önbellek durumu:"
    run_occ config:system:get memcache.local 2>/dev/null || echo "Local cache: none"
    run_occ config:system:get memcache.distributed 2>/dev/null || echo "Distributed cache: none"
    run_occ config:system:get memcache.locking 2>/dev/null || echo "Locking cache: none"
}

# ==================================================
# File Management
# ==================================================
manage_files() {
    print_section "📊 Dosya Yönetimi"
    
    echo "1. Toplam dosya sayısı hesaplanıyor..."
    docker exec postgres psql -U nextcloud -d nextcloud -c "
        SELECT COUNT(*) as total_files FROM oc_filecache WHERE mimetype != 2;
    " 2>/dev/null || echo "Sayı alınamadı"
    
    echo ""
    echo "2. Kullanıcı bazlı depolama kullanımı:"
    run_occ user:list | while read user; do
        username=$(echo "$user" | cut -d: -f1 | xargs)
        if [ -n "$username" ]; then
            quota=$(run_occ user:info "$username" 2>/dev/null | grep "quota:" || echo "unknown")
            echo "  $username: $quota"
        fi
    done 2>/dev/null || echo "Kullanıcı bilgisi alınamadı"
    
    echo ""
    echo "3. En büyük 10 dosya:"
    docker exec postgres psql -U nextcloud -d nextcloud -c "
        SELECT 
            path,
            pg_size_pretty(size) as size
        FROM oc_filecache 
        WHERE size > 0 
        ORDER BY size DESC 
        LIMIT 10;
    " 2>/dev/null || echo "Bilgi alınamadı"
    
    echo ""
    read -p "Çöp kutularını temizle? (e/h): " clean_trash
    if [ "$clean_trash" = "e" ]; then
        echo "Çöp kutuları temizleniyor..."
        run_occ trashbin:cleanup --all-users
        echo -e "${GREEN}✓ Çöp kutuları temizlendi${NC}"
    fi
    
    echo ""
    read -p "Sürüm geçmişini temizle (versioning)? (e/h): " clean_versions
    if [ "$clean_versions" = "e" ]; then
        echo "Sürüm geçmişi temizleniyor..."
        run_occ versions:cleanup 2>/dev/null || true
        echo -e "${GREEN}✓ Sürüm geçmişi temizlendi${NC}"
    fi
}

# ==================================================
# Performance Report
# ==================================================
show_performance_report() {
    print_section "📈 Performans Raporu"
    
    echo "=== Sistem Durumu ==="
    echo ""
    
    echo "1. Container Durumları:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Size}}" | grep -E "(nextcloud|postgres|redis|nginx)"
    
    echo ""
    echo "2. Bellek Kullanımı:"
    docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep -E "(nextcloud|postgres|redis|nginx|CONTAINER)"
    
    echo ""
    echo "3. Disk Kullanımı (NFS):"
    df -h | grep -E "(Filesystem|nextcloud)"
    
    echo ""
    echo "4. PostgreSQL Bağlantıları:"
    docker exec postgres psql -U nextcloud -d nextcloud -c "SELECT count(*) as connections FROM pg_stat_activity;" 2>/dev/null || echo "Bilgi alınamadı"
    
    echo ""
    echo "5. Nextcloud Durum:"
    run_occ status
    
    echo ""
    echo "6. Arkaplan İşleri:"
    run_occ background:job:list 2>/dev/null | head -20 || echo "İş listesi alınamadı"
}

# ==================================================
# Full Optimization
# ==================================================
full_optimization() {
    print_section "🚀 Tam Optimizasyon"
    
    echo -e "${YELLOW}Bu işlem şunları yapacak:${NC}"
    echo "  - Veritabanı indekslerini ekle"
    echo "  - Veritabanı optimize et"
    echo "  - Önbellek temizle"
    echo "  - Arkaplan işlerini kontrol et"
    echo ""
    read -p "Devam? (e/h): " confirm
    
    if [ "$confirm" != "e" ]; then
        return
    fi
    
    echo ""
    echo "1/5 Veritabanı indeksleri..."
    run_occ db:add-missing-indices
    
    echo ""
    echo "2/5 Veritabanı kolonları..."
    run_occ db:add-missing-columns 2>/dev/null || true
    
    echo ""
    echo "3/5 Dosya önbelleği onarılıyor..."
    run_occ files:cleanup
    
    echo ""
    echo "4/5 Arkaplan işleri modu..."
    run_occ background:cron
    
    echo ""
    echo "5/5 Sistem kontrol..."
    run_occ maintenance:repair
    
    echo ""
    echo -e "${GREEN}✓ Tam optimizasyon tamamlandı!${NC}"
}

# ==================================================
# Background Jobs Status
# ==================================================
show_background_jobs() {
    print_section "⚙️ Arkaplan Görevleri"
    
    echo "1. Cron durumu:"
    run_occ background:job:list 2>/dev/null | head -30 || echo "Liste alınamadı"
    
    echo ""
    echo "2. Son çalışan işler:"
    docker exec postgres psql -U nextcloud -d nextcloud -c "
        SELECT 
            class,
            last_run,
            last_checked
        FROM oc_jobs 
        ORDER BY last_run DESC 
        LIMIT 10;
    " 2>/dev/null || echo "Bilgi alınamadı"
    
    echo ""
    echo "3. Cron container durumu:"
    docker ps --filter name=nextcloud-cron --format "{{.Status}}"
}

# ==================================================
# Main Loop
# ==================================================
main() {
    cd "$PROJECT_DIR" 2>/dev/null || cd /opt/nextcloud
    
    while true; do
        show_menu
        
        case $choice in
            1)
                scan_files_menu
                ;;
            2)
                optimize_database
                ;;
            3)
                manage_cache
                ;;
            4)
                manage_files
                ;;
            5)
                show_performance_report
                ;;
            6)
                full_optimization
                ;;
            7)
                show_background_jobs
                ;;
            0)
                echo "Çıkış..."
                exit 0
                ;;
            *)
                echo -e "${RED}Geçersiz seçim!${NC}"
                ;;
        esac
        
        echo ""
        read -p "Devam etmek için Enter'a basın..."
    done
}

main "$@"
