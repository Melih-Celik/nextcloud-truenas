#!/bin/bash
# ==================================================
# Nextcloud + TrueNAS İnteraktif Kurulum Scripti
# ==================================================
# Bu script tüm kurulum sürecini interaktif olarak yönetir
# Çalıştırma: ./setup.sh
# ==================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.install-config"

# ==================================================
# Helper Functions
# ==================================================

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     🗄️  Nextcloud + TrueNAS Kurulum Sihirbazı               ║"
    echo "║        60TB Self-Hosted Bulut Depolama Çözümü                ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Yes/No prompt with default
ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [ "$default" = "y" ]; then
        prompt="$prompt [E/h]: "
    else
        prompt="$prompt [e/H]: "
    fi
    
    read -p "$prompt" response
    response=${response:-$default}
    
    case "$response" in
        [eEyY]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Input with default value
ask_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local response
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " response
        response=${response:-$default}
    else
        read -p "$prompt: " response
    fi
    
    eval "$var_name='$response'"
}

# Password input (hidden)
ask_password() {
    local prompt="$1"
    local var_name="$2"
    local confirm="$3"
    local password
    local password2
    
    while true; do
        read -s -p "$prompt: " password
        echo ""
        
        if [ "$confirm" = "true" ]; then
            read -s -p "Şifreyi tekrar girin: " password2
            echo ""
            
            if [ "$password" != "$password2" ]; then
                print_error "Şifreler eşleşmiyor! Tekrar deneyin."
                continue
            fi
        fi
        
        if [ -z "$password" ]; then
            print_error "Şifre boş olamaz!"
            continue
        fi
        
        break
    done
    
    eval "$var_name='$password'"
}

# Generate random password
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

# Validate IP address
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Validate domain
validate_domain() {
    local domain="$1"
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# ==================================================
# Configuration Collection
# ==================================================

collect_network_config() {
    print_section "📡 Ağ Yapılandırması"
    
    # Nextcloud Server IP
    local current_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    ask_input "Nextcloud sunucu IP adresi" "$current_ip" NEXTCLOUD_SERVER_IP
    
    while ! validate_ip "$NEXTCLOUD_SERVER_IP"; do
        print_error "Geçersiz IP adresi!"
        ask_input "Nextcloud sunucu IP adresi" "$current_ip" NEXTCLOUD_SERVER_IP
    done
    
    # TrueNAS IP
    ask_input "TrueNAS sunucu IP adresi" "192.168.1.20" TRUENAS_IP
    
    while ! validate_ip "$TRUENAS_IP"; do
        print_error "Geçersiz IP adresi!"
        ask_input "TrueNAS sunucu IP adresi" "192.168.1.20" TRUENAS_IP
    done
    
    print_success "Ağ yapılandırması tamamlandı"
}

collect_domain_config() {
    print_section "🌐 Domain ve SSL Yapılandırması"
    
    if ask_yes_no "Dış erişim için domain kullanacak mısınız?" "y"; then
        USE_DOMAIN="true"
        
        ask_input "Domain adresi (örn: cloud.example.com)" "" DOMAIN_NAME
        
        while ! validate_domain "$DOMAIN_NAME"; do
            print_error "Geçersiz domain adresi!"
            ask_input "Domain adresi" "" DOMAIN_NAME
        done
        
        ask_input "SSL sertifikası için e-posta" "admin@$DOMAIN_NAME" SSL_EMAIL
        
        # Trusted domains
        TRUSTED_DOMAINS="localhost,$DOMAIN_NAME,$NEXTCLOUD_SERVER_IP"
    else
        USE_DOMAIN="false"
        DOMAIN_NAME=""
        SSL_EMAIL=""
        TRUSTED_DOMAINS="localhost,$NEXTCLOUD_SERVER_IP"
    fi
    
    print_success "Domain yapılandırması tamamlandı"
}

collect_proxy_config() {
    print_section "🔀 Reverse Proxy Yapılandırması"
    
    echo "Nextcloud'a nasıl erişim sağlanacak?"
    echo ""
    echo "  1) Doğrudan erişim (HTTP - Sadece yerel ağ)"
    echo "  2) Nginx Proxy Manager (NPM) üzerinden (Önerilen)"
    echo "  3) Harici reverse proxy (Traefik, Caddy, vb.)"
    echo ""
    
    read -p "Seçiminiz [1-3] (varsayılan: 2): " proxy_choice
    proxy_choice=${proxy_choice:-2}
    
    case $proxy_choice in
        1)
            USE_REVERSE_PROXY="false"
            PROXY_TYPE="none"
            print_info "Doğrudan HTTP erişimi seçildi. SSL kullanılmayacak."
            ;;
        2)
            USE_REVERSE_PROXY="true"
            PROXY_TYPE="npm"
            print_info "Nginx Proxy Manager kullanılacak."
            
            if ask_yes_no "NPM aynı sunucuda Docker ile kurulsun mu?" "n"; then
                INSTALL_NPM="true"
                ask_input "NPM Admin Panel portu" "81" NPM_ADMIN_PORT
                ask_input "NPM HTTP portu" "80" NPM_HTTP_PORT
                ask_input "NPM HTTPS portu" "443" NPM_HTTPS_PORT
            else
                INSTALL_NPM="false"
                ask_input "NPM sunucu adresi (IP veya hostname)" "" NPM_HOST
            fi
            ;;
        3)
            USE_REVERSE_PROXY="true"
            PROXY_TYPE="external"
            INSTALL_NPM="false"
            print_info "Harici reverse proxy kullanılacak."
            ask_input "Proxy sunucu IP adresi veya subnet (örn: 172.20.0.0/16)" "172.20.0.0/16" PROXY_TRUSTED_NETWORK
            ;;
    esac
    
    print_success "Proxy yapılandırması tamamlandı"
}

collect_storage_config() {
    print_section "💾 Depolama Yapılandırması"
    
    # NFS Export paths
    print_info "TrueNAS NFS export yollarını girin:"
    ask_input "Nextcloud data export yolu" "/mnt/storage/nextcloud/data" NFS_DATA_EXPORT
    
    # Mount points
    ask_input "Yerel data mount noktası" "/mnt/nextcloud-data" NFS_DATA_MOUNT
    
    # Project directory
    ask_input "Nextcloud proje dizini" "/opt/nextcloud" PROJECT_DIR
    
    print_success "Depolama yapılandırması tamamlandı"
}

collect_nextcloud_config() {
    print_section "☁️ Nextcloud Yapılandırması"
    
    # Admin user
    ask_input "Nextcloud admin kullanıcı adı" "admin" NEXTCLOUD_ADMIN_USER
    
    echo ""
    print_info "Admin şifresi için:"
    echo "  1) Otomatik güçlü şifre oluştur (Önerilen)"
    echo "  2) Manuel şifre gir"
    echo ""
    
    read -p "Seçiminiz [1-2] (varsayılan: 1): " pass_choice
    pass_choice=${pass_choice:-1}
    
    if [ "$pass_choice" = "1" ]; then
        NEXTCLOUD_ADMIN_PASSWORD=$(generate_password 16)
        print_success "Admin şifresi otomatik oluşturuldu"
    else
        ask_password "Nextcloud admin şifresi" NEXTCLOUD_ADMIN_PASSWORD "true"
    fi
    
    # PHP Settings
    echo ""
    print_info "PHP Ayarları:"
    ask_input "PHP Memory Limit" "1024M" PHP_MEMORY_LIMIT
    ask_input "Maksimum dosya yükleme boyutu" "16G" PHP_UPLOAD_LIMIT
    
    print_success "Nextcloud yapılandırması tamamlandı"
}

collect_database_config() {
    print_section "🗄️ Veritabanı Yapılandırması"
    
    # Database settings
    ask_input "PostgreSQL veritabanı adı" "nextcloud" POSTGRES_DB
    ask_input "PostgreSQL kullanıcı adı" "nextcloud" POSTGRES_USER
    
    echo ""
    print_info "Veritabanı şifresi için:"
    echo "  1) Otomatik güçlü şifre oluştur (Önerilen)"
    echo "  2) Manuel şifre gir"
    echo ""
    
    read -p "Seçiminiz [1-2] (varsayılan: 1): " db_pass_choice
    db_pass_choice=${db_pass_choice:-1}
    
    if [ "$db_pass_choice" = "1" ]; then
        POSTGRES_PASSWORD=$(generate_password 32)
        print_success "PostgreSQL şifresi otomatik oluşturuldu"
    else
        ask_password "PostgreSQL şifresi" POSTGRES_PASSWORD "true"
    fi
    
    # Redis settings
    echo ""
    print_info "Redis şifresi için:"
    echo "  1) Otomatik güçlü şifre oluştur (Önerilen)"
    echo "  2) Manuel şifre gir"
    echo ""
    
    read -p "Seçiminiz [1-2] (varsayılan: 1): " redis_pass_choice
    redis_pass_choice=${redis_pass_choice:-1}
    
    if [ "$redis_pass_choice" = "1" ]; then
        REDIS_PASSWORD=$(generate_password 32)
        print_success "Redis şifresi otomatik oluşturuldu"
    else
        ask_password "Redis şifresi" REDIS_PASSWORD "true"
    fi
    
    print_success "Veritabanı yapılandırması tamamlandı"
}

collect_email_config() {
    print_section "📧 E-posta Yapılandırması (Opsiyonel)"
    
    if ask_yes_no "E-posta bildirimleri yapılandırılsın mı?" "n"; then
        CONFIGURE_SMTP="true"
        
        ask_input "SMTP sunucu adresi" "smtp.gmail.com" SMTP_HOST
        ask_input "SMTP port" "587" SMTP_PORT
        ask_input "SMTP güvenlik (tls/ssl/none)" "tls" SMTP_SECURE
        ask_input "SMTP kullanıcı adı (e-posta)" "" SMTP_USER
        ask_password "SMTP şifresi (App Password önerilir)" SMTP_PASSWORD "false"
        ask_input "Gönderen e-posta adresi" "$SMTP_USER" SMTP_FROM
    else
        CONFIGURE_SMTP="false"
    fi
    
    print_success "E-posta yapılandırması tamamlandı"
}

collect_security_config() {
    print_section "🔐 Güvenlik Yapılandırması"
    
    # Fail2ban
    if ask_yes_no "Fail2ban kurulsun mu? (Brute-force koruması)" "y"; then
        INSTALL_FAIL2BAN="true"
        ask_input "Fail2ban max deneme sayısı" "5" FAIL2BAN_MAXRETRY
        ask_input "Fail2ban ban süresi (saniye)" "86400" FAIL2BAN_BANTIME
    else
        INSTALL_FAIL2BAN="false"
    fi
    
    # Firewall
    if ask_yes_no "Firewall (firewalld) yapılandırılsın mı?" "y"; then
        CONFIGURE_FIREWALL="true"
    else
        CONFIGURE_FIREWALL="false"
    fi
    
    # Auto updates
    if ask_yes_no "Otomatik güvenlik güncellemeleri etkinleştirilsin mi?" "y"; then
        ENABLE_AUTO_UPDATES="true"
    else
        ENABLE_AUTO_UPDATES="false"
    fi
    
    print_success "Güvenlik yapılandırması tamamlandı"
}

collect_backup_config() {
    print_section "💾 Yedekleme Yapılandırması"
    
    if ask_yes_no "Otomatik yedekleme yapılandırılsın mı?" "y"; then
        CONFIGURE_BACKUP="true"
        
        ask_input "Yedekleme dizini" "/opt/nextcloud/backups" BACKUP_DIR
        ask_input "Yedek saklama süresi (gün)" "30" BACKUP_RETENTION_DAYS
        
        echo ""
        print_info "TrueNAS ZFS snapshot için SSH erişimi:"
        if ask_yes_no "TrueNAS'a SSH ile ZFS snapshot alınsın mı?" "n"; then
            ENABLE_ZFS_SNAPSHOT="true"
            ask_input "TrueNAS SSH kullanıcısı" "admin" TRUENAS_SSH_USER
        else
            ENABLE_ZFS_SNAPSHOT="false"
        fi
    else
        CONFIGURE_BACKUP="false"
    fi
    
    print_success "Yedekleme yapılandırması tamamlandı"
}

collect_advanced_config() {
    print_section "⚙️ Gelişmiş Ayarlar"
    
    if ask_yes_no "Gelişmiş ayarları yapılandırmak ister misiniz?" "n"; then
        # Nextcloud version
        ask_input "Nextcloud Docker tag" "29-fpm-alpine" NEXTCLOUD_TAG
        
        # PostgreSQL version
        ask_input "PostgreSQL Docker tag" "16-alpine" POSTGRES_TAG
        
        # Redis version
        ask_input "Redis Docker tag" "7-alpine" REDIS_TAG
        
        # Timezone
        ask_input "Timezone" "Europe/Istanbul" TIMEZONE
        
        # Phone region
        ask_input "Varsayılan telefon bölgesi (ISO 3166-1)" "TR" DEFAULT_PHONE_REGION
    else
        NEXTCLOUD_TAG="29-fpm-alpine"
        POSTGRES_TAG="16-alpine"
        REDIS_TAG="7-alpine"
        TIMEZONE="Europe/Istanbul"
        DEFAULT_PHONE_REGION="TR"
    fi
    
    print_success "Gelişmiş ayarlar tamamlandı"
}

# ==================================================
# Configuration Summary & Save
# ==================================================

show_config_summary() {
    print_section "📋 Yapılandırma Özeti"
    
    echo -e "${BOLD}Ağ Ayarları:${NC}"
    echo "  Nextcloud Sunucu IP : $NEXTCLOUD_SERVER_IP"
    echo "  TrueNAS IP          : $TRUENAS_IP"
    echo ""
    
    echo -e "${BOLD}Domain & SSL:${NC}"
    if [ "$USE_DOMAIN" = "true" ]; then
        echo "  Domain              : $DOMAIN_NAME"
        echo "  SSL E-posta         : $SSL_EMAIL"
    else
        echo "  Domain              : Kullanılmıyor"
    fi
    echo "  Trusted Domains     : $TRUSTED_DOMAINS"
    echo ""
    
    echo -e "${BOLD}Reverse Proxy:${NC}"
    case $PROXY_TYPE in
        none)
            echo "  Tip                 : Doğrudan erişim (HTTP)"
            ;;
        npm)
            echo "  Tip                 : Nginx Proxy Manager"
            if [ "$INSTALL_NPM" = "true" ]; then
                echo "  NPM Kurulumu        : Bu sunucuda"
                echo "  NPM Admin Port      : $NPM_ADMIN_PORT"
            else
                echo "  NPM Adresi          : $NPM_HOST"
            fi
            ;;
        external)
            echo "  Tip                 : Harici Proxy"
            echo "  Trusted Network     : $PROXY_TRUSTED_NETWORK"
            ;;
    esac
    echo ""
    
    echo -e "${BOLD}Depolama:${NC}"
    echo "  NFS Data Export     : $NFS_DATA_EXPORT"
    echo "  Data Mount Noktası  : $NFS_DATA_MOUNT"
    echo "  Proje Dizini        : $PROJECT_DIR"
    echo ""
    
    echo -e "${BOLD}Nextcloud:${NC}"
    echo "  Admin Kullanıcı     : $NEXTCLOUD_ADMIN_USER"
    echo "  Admin Şifre         : ********"
    echo "  PHP Memory Limit    : $PHP_MEMORY_LIMIT"
    echo "  Upload Limit        : $PHP_UPLOAD_LIMIT"
    echo ""
    
    echo -e "${BOLD}Veritabanı:${NC}"
    echo "  PostgreSQL DB       : $POSTGRES_DB"
    echo "  PostgreSQL User     : $POSTGRES_USER"
    echo "  PostgreSQL Şifre    : ********"
    echo "  Redis Şifre         : ********"
    echo ""
    
    echo -e "${BOLD}Güvenlik:${NC}"
    echo "  Fail2ban            : ${INSTALL_FAIL2BAN:-false}"
    echo "  Firewall            : ${CONFIGURE_FIREWALL:-false}"
    echo "  Auto Updates        : ${ENABLE_AUTO_UPDATES:-false}"
    echo ""
    
    echo -e "${BOLD}Yedekleme:${NC}"
    echo "  Otomatik Yedekleme  : ${CONFIGURE_BACKUP:-false}"
    if [ "${CONFIGURE_BACKUP:-false}" = "true" ]; then
        echo "  Yedek Dizini        : $BACKUP_DIR"
        echo "  Saklama Süresi      : $BACKUP_RETENTION_DAYS gün"
        echo "  ZFS Snapshot        : ${ENABLE_ZFS_SNAPSHOT:-false}"
    fi
    echo ""
}

save_config() {
    print_section "💾 Yapılandırma Kaydediliyor"
    
    cat > "$CONFIG_FILE" << EOF
# Nextcloud + TrueNAS Kurulum Yapılandırması
# Oluşturulma: $(date)
# DİKKAT: Bu dosya hassas bilgiler içerir!

# ==== Ağ Ayarları ====
NEXTCLOUD_SERVER_IP="$NEXTCLOUD_SERVER_IP"
TRUENAS_IP="$TRUENAS_IP"

# ==== Domain & SSL ====
USE_DOMAIN="$USE_DOMAIN"
DOMAIN_NAME="$DOMAIN_NAME"
SSL_EMAIL="$SSL_EMAIL"
TRUSTED_DOMAINS="$TRUSTED_DOMAINS"

# ==== Reverse Proxy ====
USE_REVERSE_PROXY="${USE_REVERSE_PROXY:-false}"
PROXY_TYPE="${PROXY_TYPE:-none}"
INSTALL_NPM="${INSTALL_NPM:-false}"
NPM_HOST="${NPM_HOST:-}"
NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-81}"
NPM_HTTP_PORT="${NPM_HTTP_PORT:-80}"
NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-443}"
PROXY_TRUSTED_NETWORK="${PROXY_TRUSTED_NETWORK:-172.20.0.0/16}"

# ==== Depolama ====
NFS_DATA_EXPORT="$NFS_DATA_EXPORT"
NFS_DATA_MOUNT="$NFS_DATA_MOUNT"
PROJECT_DIR="$PROJECT_DIR"

# ==== Nextcloud ====
NEXTCLOUD_ADMIN_USER="$NEXTCLOUD_ADMIN_USER"
NEXTCLOUD_ADMIN_PASSWORD="$NEXTCLOUD_ADMIN_PASSWORD"
PHP_MEMORY_LIMIT="$PHP_MEMORY_LIMIT"
PHP_UPLOAD_LIMIT="$PHP_UPLOAD_LIMIT"
NEXTCLOUD_TAG="${NEXTCLOUD_TAG:-29-fpm-alpine}"

# ==== Veritabanı ====
POSTGRES_DB="$POSTGRES_DB"
POSTGRES_USER="$POSTGRES_USER"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
POSTGRES_TAG="${POSTGRES_TAG:-16-alpine}"
REDIS_PASSWORD="$REDIS_PASSWORD"
REDIS_TAG="${REDIS_TAG:-7-alpine}"

# ==== E-posta ====
CONFIGURE_SMTP="${CONFIGURE_SMTP:-false}"
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_SECURE="${SMTP_SECURE:-tls}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
SMTP_FROM="${SMTP_FROM:-}"

# ==== Güvenlik ====
INSTALL_FAIL2BAN="${INSTALL_FAIL2BAN:-true}"
FAIL2BAN_MAXRETRY="${FAIL2BAN_MAXRETRY:-5}"
FAIL2BAN_BANTIME="${FAIL2BAN_BANTIME:-86400}"
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-true}"
ENABLE_AUTO_UPDATES="${ENABLE_AUTO_UPDATES:-true}"

# ==== Yedekleme ====
CONFIGURE_BACKUP="${CONFIGURE_BACKUP:-true}"
BACKUP_DIR="${BACKUP_DIR:-/opt/nextcloud/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
ENABLE_ZFS_SNAPSHOT="${ENABLE_ZFS_SNAPSHOT:-false}"
TRUENAS_SSH_USER="${TRUENAS_SSH_USER:-admin}"

# ==== Diğer ====
TIMEZONE="${TIMEZONE:-Europe/Istanbul}"
DEFAULT_PHONE_REGION="${DEFAULT_PHONE_REGION:-TR}"
EOF
    
    chmod 600 "$CONFIG_FILE"
    print_success "Yapılandırma kaydedildi: $CONFIG_FILE"
}

# ==================================================
# File Generation
# ==================================================

generate_env_file() {
    print_info ".env dosyası oluşturuluyor..."
    
    local env_file="$SCRIPT_DIR/docker/.env"
    
    cat > "$env_file" << EOF
# ==================================================
# NEXTCLOUD + TRUENAS ENVIRONMENT CONFIGURATION
# ==================================================
# Otomatik oluşturuldu: $(date)
# Bu dosyayı version control'e EKLEMEYİN!
# ==================================================

# --------------------------------------------------
# NEXTCLOUD SETTINGS
# --------------------------------------------------

NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER
NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
NEXTCLOUD_TRUSTED_DOMAINS=$TRUSTED_DOMAINS

# --------------------------------------------------
# DATABASE SETTINGS (PostgreSQL)
# --------------------------------------------------

POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# --------------------------------------------------
# REDIS CACHE SETTINGS
# --------------------------------------------------

REDIS_PASSWORD=$REDIS_PASSWORD

# --------------------------------------------------
# PHP SETTINGS
# --------------------------------------------------

PHP_MEMORY_LIMIT=$PHP_MEMORY_LIMIT
PHP_UPLOAD_LIMIT=$PHP_UPLOAD_LIMIT

# --------------------------------------------------
# TRUENAS NFS SETTINGS
# --------------------------------------------------

TRUENAS_IP=$TRUENAS_IP

# --------------------------------------------------
# DOMAIN / SSL SETTINGS
# --------------------------------------------------

DOMAIN_NAME=${DOMAIN_NAME:-localhost}
SSL_EMAIL=${SSL_EMAIL:-}

# --------------------------------------------------
# DOCKER IMAGE TAGS
# --------------------------------------------------

NEXTCLOUD_TAG=$NEXTCLOUD_TAG
POSTGRES_TAG=$POSTGRES_TAG
REDIS_TAG=$REDIS_TAG

# --------------------------------------------------
# SMTP SETTINGS (optional)
# --------------------------------------------------

SMTP_HOST=${SMTP_HOST:-}
SMTP_PORT=${SMTP_PORT:-587}
SMTP_SECURE=${SMTP_SECURE:-tls}
SMTP_USER=${SMTP_USER:-}
SMTP_PASSWORD=${SMTP_PASSWORD:-}
SMTP_FROM=${SMTP_FROM:-}
EOF
    
    chmod 600 "$env_file"
    print_success ".env dosyası oluşturuldu"
}

generate_docker_compose_override() {
    # NPM kurulacaksa override dosyası oluştur
    if [ "$INSTALL_NPM" = "true" ]; then
        print_info "docker-compose.override.yml oluşturuluyor (NPM dahil)..."
        
        cat > "$SCRIPT_DIR/docker/docker-compose.override.yml" << EOF
# Docker Compose Override - Nginx Proxy Manager dahil
# Otomatik oluşturuldu: $(date)

services:
  # Nginx Proxy Manager
  npm:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - '${NPM_HTTP_PORT}:80'
      - '${NPM_HTTPS_PORT}:443'
      - '${NPM_ADMIN_PORT}:81'
    volumes:
      - npm-data:/data
      - npm-letsencrypt:/etc/letsencrypt
    networks:
      - nextcloud-network
    healthcheck:
      test: ["CMD", "/bin/check-health"]
      interval: 10s
      timeout: 3s

  # Nginx'in port binding'ini kaldır (NPM üzerinden erişim)
  nginx:
    ports: []

volumes:
  npm-data:
  npm-letsencrypt:
EOF
        
        print_success "docker-compose.override.yml oluşturuldu"
    fi
}

# ==================================================
# Installation Steps
# ==================================================

run_installation() {
    print_section "🚀 Kurulum Başlıyor"
    
    echo "Kurulum adımları:"
    echo ""
    echo "  1. Host hazırlığı (Docker, NFS, güvenlik)"
    echo "  2. NFS mount yapılandırması"
    echo "  3. Nextcloud deployment"
    echo ""
    
    if ! ask_yes_no "Kuruluma devam etmek istiyor musunuz?" "y"; then
        print_warning "Kurulum iptal edildi."
        echo ""
        echo "Yapılandırma dosyası kaydedildi: $CONFIG_FILE"
        echo "Daha sonra kurulumu başlatmak için:"
        echo "  ./setup.sh --install"
        exit 0
    fi
    
    # Check if running as root for installation
    if [ "$EUID" -ne 0 ]; then
        print_warning "Kurulum için root yetkisi gerekiyor."
        echo "Lütfen şu komutu çalıştırın:"
        echo "  sudo ./setup.sh --install"
        exit 1
    fi
    
    # Step 1: Prepare host
    echo ""
    print_info "Adım 1/3: Host hazırlanıyor..."
    if [ -f "$SCRIPT_DIR/scripts/01-prepare-host.sh" ]; then
        export INSTALL_FAIL2BAN CONFIGURE_FIREWALL ENABLE_AUTO_UPDATES
        bash "$SCRIPT_DIR/scripts/01-prepare-host.sh"
    fi
    
    # Step 2: Mount NFS
    echo ""
    print_info "Adım 2/3: NFS mount yapılandırılıyor..."
    if [ -f "$SCRIPT_DIR/scripts/02-mount-nfs.sh" ]; then
        export TRUENAS_IP NFS_DATA_EXPORT NFS_DATA_MOUNT
        bash "$SCRIPT_DIR/scripts/02-mount-nfs.sh"
    fi
    
    # Step 3: Deploy Nextcloud
    echo ""
    print_info "Adım 3/3: Nextcloud deploy ediliyor..."
    if [ -f "$SCRIPT_DIR/scripts/03-deploy.sh" ]; then
        export PROJECT_DIR
        bash "$SCRIPT_DIR/scripts/03-deploy.sh"
    fi
    
    print_section "✅ Kurulum Tamamlandı!"
    show_completion_info
}

show_completion_info() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  🎉 Nextcloud kurulumu başarıyla tamamlandı!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Erişim Bilgileri:${NC}"
    if [ "$USE_DOMAIN" = "true" ]; then
        echo "  URL       : https://$DOMAIN_NAME"
    else
        echo "  URL       : http://$NEXTCLOUD_SERVER_IP"
    fi
    echo "  Kullanıcı : $NEXTCLOUD_ADMIN_USER"
    echo "  Şifre     : $NEXTCLOUD_ADMIN_PASSWORD"
    echo ""
    
    if [ "$INSTALL_NPM" = "true" ]; then
        echo -e "${BOLD}Nginx Proxy Manager:${NC}"
        echo "  URL       : http://$NEXTCLOUD_SERVER_IP:$NPM_ADMIN_PORT"
        echo "  E-posta   : admin@example.com"
        echo "  Şifre     : changeme"
        echo ""
        print_warning "NPM'de ilk girişte şifrenizi değiştirmeyi unutmayın!"
        echo ""
    fi
    
    echo -e "${BOLD}Önemli Dosyalar:${NC}"
    echo "  Yapılandırma  : $CONFIG_FILE"
    echo "  Environment   : $SCRIPT_DIR/docker/.env"
    echo "  Docker Compose: $PROJECT_DIR/docker-compose.yml"
    echo ""
    
    echo -e "${BOLD}Faydalı Komutlar:${NC}"
    echo "  Durum kontrol : ./scripts/health-check.sh"
    echo "  Yedekleme     : ./scripts/backup.sh"
    echo "  Loglar        : cd $PROJECT_DIR && docker compose logs -f"
    echo ""
    
    print_warning "GÜVENLİK: .env ve .install-config dosyalarını güvende tutun!"
    echo ""
}

# ==================================================
# Main Menu
# ==================================================

show_main_menu() {
    print_banner
    
    echo "  Hoş geldiniz! Bu sihirbaz Nextcloud kurulumunu yapılandırmanıza"
    echo "  yardımcı olacaktır."
    echo ""
    echo "  Seçenekler:"
    echo ""
    echo "    1) Yeni kurulum - Tüm yapılandırmayı baştan yap"
    echo "    2) Mevcut yapılandırmayı kullan"
    echo "    3) Sadece dosyaları oluştur (kurulum yapma)"
    echo "    4) Yapılandırmayı görüntüle"
    echo "    5) Çıkış"
    echo ""
    
    read -p "  Seçiminiz [1-5]: " menu_choice
    
    case $menu_choice in
        1)
            run_full_setup
            ;;
        2)
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
                show_config_summary
                if ask_yes_no "Bu yapılandırma ile devam edilsin mi?" "y"; then
                    generate_env_file
                    generate_docker_compose_override
                    run_installation
                fi
            else
                print_error "Mevcut yapılandırma bulunamadı!"
                echo "Yeni kurulum için 1'i seçin."
            fi
            ;;
        3)
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
            else
                run_config_collection
            fi
            generate_env_file
            generate_docker_compose_override
            print_success "Dosyalar oluşturuldu!"
            echo "Kurulumu başlatmak için: sudo ./setup.sh --install"
            ;;
        4)
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
                show_config_summary
            else
                print_error "Yapılandırma dosyası bulunamadı!"
            fi
            ;;
        5)
            echo "Güle güle!"
            exit 0
            ;;
        *)
            print_error "Geçersiz seçim!"
            show_main_menu
            ;;
    esac
}

run_config_collection() {
    collect_network_config
    collect_domain_config
    collect_proxy_config
    collect_storage_config
    collect_nextcloud_config
    collect_database_config
    collect_email_config
    collect_security_config
    collect_backup_config
    collect_advanced_config
}

run_full_setup() {
    print_banner
    
    echo "  Bu sihirbaz size aşağıdaki konularda sorular soracak:"
    echo ""
    echo "    • Ağ yapılandırması (IP adresleri)"
    echo "    • Domain ve SSL ayarları"
    echo "    • Reverse proxy seçimi"
    echo "    • Depolama yapılandırması"
    echo "    • Nextcloud ayarları"
    echo "    • Veritabanı yapılandırması"
    echo "    • E-posta ayarları"
    echo "    • Güvenlik ayarları"
    echo "    • Yedekleme yapılandırması"
    echo ""
    
    if ! ask_yes_no "Devam etmek istiyor musunuz?" "y"; then
        exit 0
    fi
    
    run_config_collection
    
    echo ""
    show_config_summary
    
    if ask_yes_no "Yapılandırma doğru mu?" "y"; then
        save_config
        generate_env_file
        generate_docker_compose_override
        
        if ask_yes_no "Kurulumu şimdi başlatmak istiyor musunuz?" "y"; then
            run_installation
        else
            echo ""
            print_success "Yapılandırma kaydedildi!"
            echo ""
            echo "Kurulumu daha sonra başlatmak için:"
            echo "  sudo ./setup.sh --install"
        fi
    else
        print_warning "Yapılandırma iptal edildi. Tekrar başlatın."
    fi
}

# ==================================================
# Command Line Arguments
# ==================================================

show_help() {
    echo "Nextcloud + TrueNAS İnteraktif Kurulum Scripti"
    echo ""
    echo "Kullanım: $0 [SEÇENEK]"
    echo ""
    echo "Seçenekler:"
    echo "  --help, -h        Bu yardım mesajını göster"
    echo "  --install, -i     Mevcut yapılandırma ile kurulumu başlat"
    echo "  --config, -c      Sadece yapılandırma topla"
    echo "  --generate, -g    Sadece dosyaları oluştur"
    echo "  --show, -s        Mevcut yapılandırmayı göster"
    echo "  --reset           Yapılandırmayı sıfırla"
    echo ""
    echo "Seçenek belirtilmezse interaktif menü açılır."
}

# ==================================================
# Entry Point
# ==================================================

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --install|-i)
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
                generate_env_file
                generate_docker_compose_override
                run_installation
            else
                print_error "Yapılandırma dosyası bulunamadı!"
                echo "Önce yapılandırma yapın: $0 --config"
                exit 1
            fi
            ;;
        --config|-c)
            run_config_collection
            show_config_summary
            if ask_yes_no "Yapılandırmayı kaydet?" "y"; then
                save_config
            fi
            ;;
        --generate|-g)
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
                generate_env_file
                generate_docker_compose_override
                print_success "Dosyalar oluşturuldu!"
            else
                print_error "Yapılandırma dosyası bulunamadı!"
                exit 1
            fi
            ;;
        --show|-s)
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
                show_config_summary
            else
                print_error "Yapılandırma dosyası bulunamadı!"
                exit 1
            fi
            ;;
        --reset)
            if [ -f "$CONFIG_FILE" ]; then
                rm -f "$CONFIG_FILE"
                print_success "Yapılandırma sıfırlandı."
            fi
            if [ -f "$SCRIPT_DIR/docker/.env" ]; then
                rm -f "$SCRIPT_DIR/docker/.env"
            fi
            ;;
        "")
            show_main_menu
            ;;
        *)
            print_error "Bilinmeyen seçenek: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
