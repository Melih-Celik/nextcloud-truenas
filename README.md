# 🗄️ Nextcloud + TrueNAS Kurumsal Dosya Paylaşım Sistemi

60TB+ kapasiteli, self-hosted kurumsal bulut depolama çözümü. Collabora Online ofis paketi, Nginx Proxy Manager SSL desteği ve TrueNAS NFS entegrasyonu ile tam teşekküllü bir dosya paylaşım platformu.

## ✨ Özellikler

| Özellik | Açıklama |
|---------|----------|
| 📁 **60TB+ Depolama** | TrueNAS ZFS üzerinde NFS ile yüksek kapasiteli depolama |
| 📝 **Collabora Online** | Tarayıcıda Word, Excel, PowerPoint düzenleme |
| 🔒 **SSL/TLS** | Nginx Proxy Manager ile Let's Encrypt sertifikaları |
| 🚀 **Yüksek Performans** | Redis cache, PostgreSQL, PHP-FPM optimizasyonları |
| 🔐 **Güvenlik** | Fail2ban, Firewall, 2FA desteği |
| 📧 **E-posta Bildirimleri** | SMTP entegrasyonu |
| 💾 **Otomatik Yedekleme** | Zamanlanmış yedekleme ve ZFS snapshot desteği |

## 🚀 Hızlı Başlangıç

```bash
# Repoyu klonlayın
git clone https://github.com/your-repo/nextcloud-truenas.git
cd nextcloud-truenas

# İnteraktif kurulum sihirbazını başlatın
./setup.sh
```

Kurulum sihirbazı tüm ayarları interaktif olarak sorar ve sistemi otomatik kurar.

## 📐 Sistem Mimarisi

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                İNTERNET                                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼ (443/HTTPS)
┌─────────────────────────────────────────────────────────────────────────────┐
│                    NEXTCLOUD SERVER (AlmaLinux 10)                           │
│                          192.168.1.10                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────────┐          │
│  │ Nginx Proxy     │  │    Collabora     │  │      Nginx         │          │
│  │ Manager (NPM)   │──│    Online        │──│   (Nextcloud)      │          │
│  │ :80, :443, :81  │  │     :9980        │  │      :8080         │          │
│  └─────────────────┘  └──────────────────┘  └────────────────────┘          │
│           │                                           │                      │
│           └───────────────────┬───────────────────────┘                      │
│                               ▼                                              │
│  ┌────────────────────────────────────────────────────────────────┐         │
│  │                    Nextcloud (PHP-FPM)                         │         │
│  │                      stable-fpm (Debian)                       │         │
│  └────────────────────────────────────────────────────────────────┘         │
│           │                               │                                  │
│           ▼                               ▼                                  │
│  ┌─────────────────┐             ┌─────────────────┐                        │
│  │   PostgreSQL    │             │      Redis      │                        │
│  │  (Local Volume) │             │     (Cache)     │                        │
│  └─────────────────┘             └─────────────────┘                        │
│           │                                                                  │
└───────────┼──────────────────────────────────────────────────────────────────┘
            │ NFS
            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      TRUENAS SERVER (NFS Storage)                            │
│                          192.168.1.20                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  /mnt/storage/nextcloud/                                                     │
│  ├── config/     ← Nextcloud yapılandırma (UID: 33)                         │
│  └── data/       ← Kullanıcı dosyaları 60TB+ (UID: 33)                      │
│                                                                              │
│  NOT: PostgreSQL veritabanı YEREL Docker volume'da tutulur                  │
│       (NFS, veritabanı için uygun değildir)                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 🐳 Docker Servisleri

| Servis | Image | Port | Açıklama |
|--------|-------|------|----------|
| **nginx** | nginx:alpine | 80/8080 | Nextcloud reverse proxy |
| **nextcloud** | nextcloud:stable-fpm | 9000 | PHP-FPM uygulaması |
| **postgres** | postgres:16-alpine | 5432 | Veritabanı (local volume) |
| **redis** | redis:7-alpine | 6379 | Session ve cache |
| **cron** | nextcloud:stable-fpm | - | Arka plan görevleri |
| **npm** *(opsiyonel)* | jc21/nginx-proxy-manager | 80,443,81 | SSL yönetimi |
| **collabora** *(opsiyonel)* | collabora/code | 9980 | Online ofis paketi |

## 📁 Proje Yapısı

```
nextcloud-truenas/
├── setup.sh                          # İnteraktif kurulum sihirbazı
├── README.md                         # Bu dosya
├── docker/
│   ├── docker-compose.yml            # Ana servisler
│   ├── docker-compose.npm.yml        # Nginx Proxy Manager
│   ├── docker-compose.collabora.yml  # Collabora Online
│   ├── .env.example                  # Ortam değişkenleri örneği
│   └── configs/
│       ├── nginx/nextcloud.conf      # Nginx yapılandırması
│       ├── php/custom.ini            # PHP ayarları
│       ├── php/redis-session.ini.template  # Redis session template
│       ├── redis/redis.conf          # Redis yapılandırması
│       └── nextcloud/hooks/          # Otomatik yapılandırma hook'ları
├── scripts/
│   ├── 01-prepare-host.sh            # Host hazırlık scripti
│   ├── 02-mount-nfs.sh               # NFS mount scripti
│   ├── 03-deploy.sh                  # Deployment scripti
│   ├── backup.sh                     # Yedekleme scripti
│   └── health-check.sh               # Sağlık kontrolü
└── docs/
    ├── 01-truenas-setup.md           # TrueNAS kurulum rehberi
    ├── 02-nextcloud-setup.md         # Nextcloud kurulum rehberi
    ├── 03-security-hardening.md      # Güvenlik yapılandırması
    ├── 04-performance-tuning.md      # Performans optimizasyonu
    └── 05-maintenance.md             # Bakım prosedürleri
```

## 🎯 Docker Compose Dosyaları

Sistem modüler yapıda tasarlanmıştır. Kurulum seçeneklerine göre farklı compose dosyaları kullanılır:

| Dosya | İçerik | Ne Zaman Kullanılır |
|-------|--------|---------------------|
| `docker-compose.yml` | nginx, nextcloud, postgres, redis, cron | **Her zaman** (temel servisler) |
| `docker-compose.npm.yml` | Nginx Proxy Manager | SSL/Let's Encrypt istenirse |
| `docker-compose.collabora.yml` | Collabora Online | Office düzenleme istenirse |

### Compose Kombinasyonları

```bash
# Sadece temel servisler
docker compose -f docker-compose.yml up -d

# Temel + NPM (SSL)
docker compose -f docker-compose.yml -f docker-compose.npm.yml up -d

# Temel + Collabora (Office)
docker compose -f docker-compose.yml -f docker-compose.collabora.yml up -d

# Temel + NPM + Collabora (Tam kurulum)
docker compose -f docker-compose.yml -f docker-compose.npm.yml -f docker-compose.collabora.yml up -d
```

## 🔧 Sistem Yönetimi

### Servisleri Başlatma

```bash
cd /opt/nextcloud

# Sadece temel servisler
docker compose up -d

# NPM dahil
docker compose -f docker-compose.yml -f docker-compose.npm.yml up -d

# Collabora dahil
docker compose -f docker-compose.yml -f docker-compose.collabora.yml up -d

# Tüm opsiyonel servisler dahil
docker compose -f docker-compose.yml -f docker-compose.npm.yml -f docker-compose.collabora.yml up -d
```

### Servisleri Durdurma

```bash
cd /opt/nextcloud

# Sadece temel servisler
docker compose down

# NPM dahil
docker compose -f docker-compose.yml -f docker-compose.npm.yml down

# Tüm servisler
docker compose -f docker-compose.yml -f docker-compose.npm.yml -f docker-compose.collabora.yml down
```

### Servisleri Yeniden Başlatma

```bash
cd /opt/nextcloud

# Tek bir servisi yeniden başlat
docker compose restart nextcloud
docker compose restart nginx
docker compose restart redis

# Tüm servisleri yeniden başlat
docker compose restart
```

### Sistem Güncelleme

```bash
cd /opt/nextcloud

# 1. Yedek al (önerilir)
./backup.sh

# 2. Yeni image'ları çek
# Sadece temel servisler
docker compose pull

# NPM dahil
docker compose -f docker-compose.yml -f docker-compose.npm.yml pull

# Collabora dahil
docker compose -f docker-compose.yml -f docker-compose.collabora.yml pull

# Tüm servisler
docker compose -f docker-compose.yml -f docker-compose.npm.yml -f docker-compose.collabora.yml pull

# 3. Servisleri güncelle ve yeniden başlat
docker compose -f docker-compose.yml -f docker-compose.npm.yml -f docker-compose.collabora.yml up -d

# 4. Nextcloud veritabanı güncellemelerini uygula
docker exec -u www-data nextcloud php occ upgrade
docker exec -u www-data nextcloud php occ db:add-missing-indices
docker exec -u www-data nextcloud php occ maintenance:repair
```

### Log İzleme

```bash
cd /opt/nextcloud

# Tüm servislerin logları
docker compose logs -f

# Belirli bir servisin logu
docker compose logs -f nextcloud
docker compose logs -f nginx
docker compose logs -f postgres
docker compose logs -f redis
docker compose logs -f collabora
docker compose logs -f npm

# Son 100 satır
docker compose logs --tail=100 nextcloud
```

### Servis Durumu

```bash
cd /opt/nextcloud

# Çalışan container'lar
docker compose ps

# Container kaynak kullanımı
docker stats
```

## 📝 Collabora Online (Office Paketi)

Collabora Online, tarayıcı içinde Word, Excel ve PowerPoint dosyalarını düzenlemenizi sağlar.

### Collabora Kurulumu

#### 1. .env Dosyasını Düzenle

```bash
# Collabora'nın public URL'i (sadece hostname, https:// OLMADAN)
COLLABORA_SERVER_NAME=office.yourdomain.com

# Nextcloud'un public URL'i (port DAHİL)
COLLABORA_WOPI_URL=https://cloud.yourdomain.com:443
```

#### 2. Container'ı Başlat

```bash
cd /opt/nextcloud
docker compose -f docker-compose.yml -f docker-compose.collabora.yml up -d collabora
```

#### 3. NPM'de Proxy Host Ekle

| Alan | Değer |
|------|-------|
| Domain Names | `office.yourdomain.com` |
| Scheme | `http` |
| Forward Hostname | `collabora` (aynı makine) veya `SUNUCU_IP` (ayrı makine) |
| Forward Port | `9980` |
| Websockets Support | ✅ (zorunlu!) |
| SSL | Let's Encrypt ile |

**Advanced sekmesi:**
```nginx
proxy_set_header Host $host;
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_read_timeout 3600;
```

#### 4. Nextcloud'da Aktifleştir

1. Ayarlar → Uygulamalar → "Nextcloud Office" yükle
2. Ayarlar → Yönetim → Nextcloud Office
3. "Use your own server" seç
4. URL: `https://office.yourdomain.com`

### Collabora Sorun Giderme

**"Unable to connect to Collabora server" hatası:**

```bash
# 1. .env değerlerini kontrol et
grep COLLABORA /opt/nextcloud/.env

# 2. Container'ı yeniden başlat
docker compose -f docker-compose.yml -f docker-compose.collabora.yml restart collabora

# 3. Discovery endpoint'i test et
curl -s http://localhost:9980/hosting/discovery | head -10

# 4. NPM'den erişimi test et (aynı makinede)
docker exec nginx-proxy-manager curl -s http://collabora:9980/hosting/discovery | head -5
```

## 🔐 Nginx Proxy Manager (SSL)

NPM, Let's Encrypt sertifikalarını otomatik yönetir.

### NPM İlk Kurulum

1. **Admin paneli:** `http://SUNUCU_IP:81`
2. **Varsayılan giriş:** `admin@example.com` / `changeme`

### Proxy Host Ayarları

#### Nextcloud için:

| Alan | NPM Aynı Makine | NPM Ayrı Makine |
|------|-----------------|-----------------|
| Domain | `cloud.yourdomain.com` | `cloud.yourdomain.com` |
| Forward Hostname | `nginx` | `SUNUCU_IP` |
| Forward Port | `8080` | `80` |

#### Collabora için:

| Alan | NPM Aynı Makine | NPM Ayrı Makine |
|------|-----------------|-----------------|
| Domain | `office.yourdomain.com` | `office.yourdomain.com` |
| Forward Hostname | `collabora` | `SUNUCU_IP` |
| Forward Port | `9980` | `9980` |

**Her iki proxy için Advanced sekmesi:**
```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
client_max_body_size 16G;
proxy_read_timeout 3600;
```

### Nextcloud Trusted Proxy Ayarları

```bash
# Docker network (NPM aynı makinede)
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 0 --value="172.20.0.0/16"

# VEYA NPM IP'si (NPM ayrı makinede)
# docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 0 --value="NPM_IP"

# Gerçek IP algılama
docker exec -u www-data nextcloud php occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR"

# HTTPS zorla
docker exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="https"
```

### Brute-Force Engeli Temizleme

```bash
docker exec -u www-data nextcloud php occ security:bruteforce:reset all
```

## 💾 Veri Depolama

### NFS Mount Noktaları

| Mount | Kaynak (TrueNAS) | Hedef (Sunucu) | Kullanım |
|-------|------------------|----------------|----------|
| config | /mnt/storage/nextcloud/config | /mnt/nextcloud/config | Nextcloud yapılandırması |
| data | /mnt/storage/nextcloud/data | /mnt/nextcloud/data | Kullanıcı dosyaları (60TB+) |

> **Not:** PostgreSQL veritabanı **lokal Docker volume**'da tutulur. NFS, veritabanı I/O için uygun değildir.

### Dosya İzinleri

Nextcloud Debian image'ı `www-data` kullanıcısını UID `33` ile çalıştırır. TrueNAS'ta:

```bash
# TrueNAS üzerinde
chown -R 33:33 /mnt/storage/nextcloud/config
chown -R 33:33 /mnt/storage/nextcloud/data
```

### Dosya Tarama

Yeni dosyalar ekledikten sonra Nextcloud'un bunları görmesi için:

```bash
# Tüm kullanıcıların dosyalarını tara
docker exec -u www-data nextcloud php occ files:scan --all

# Belirli bir kullanıcının dosyalarını tara
docker exec -u www-data nextcloud php occ files:scan USERNAME

# Arka planda tarama (büyük veri setleri için)
docker exec -u www-data nextcloud php occ files:scan --all &
```

## 🔧 Nextcloud OCC Komutları

```bash
# Maintenance mode aç/kapa
docker exec -u www-data nextcloud php occ maintenance:mode --on
docker exec -u www-data nextcloud php occ maintenance:mode --off

# Veritabanı indekslerini ekle
docker exec -u www-data nextcloud php occ db:add-missing-indices

# BigInt dönüşümü (büyük dosya ID'leri için)
docker exec -u www-data nextcloud php occ db:convert-filecache-bigint

# Cache temizle
docker exec -u www-data nextcloud php occ files:cleanup
docker exec -u www-data nextcloud php occ trashbin:cleanup --all-users

# Sistem durumu
docker exec -u www-data nextcloud php occ status

# Yapılandırma listele
docker exec -u www-data nextcloud php occ config:list

# Trusted domain ekle
docker exec -u www-data nextcloud php occ config:system:set trusted_domains 2 --value="yeni.domain.com"
```

## 🛠️ Sorun Giderme

### Container Başlamıyor

```bash
# Detaylı log
docker compose logs nextcloud

# Container içine gir
docker exec -it nextcloud bash

# Servis durumunu kontrol et
docker compose ps
```

### NFS Bağlantı Sorunları

```bash
# NFS mount durumu
mount | grep nfs

# Manuel mount
sudo mount -t nfs TRUENAS_IP:/mnt/storage/nextcloud/data /mnt/nextcloud/data

# NFS test
showmount -e TRUENAS_IP
```

### Redis Bağlantı Sorunları

```bash
# Redis ping
docker exec redis redis-cli -a REDIS_PASSWORD ping

# Redis bilgi
docker exec redis redis-cli -a REDIS_PASSWORD info
```

### Veritabanı Sorunları

```bash
# PostgreSQL'e bağlan
docker exec -it postgres psql -U nextcloud -d nextcloud

# Veritabanı boyutu
docker exec postgres psql -U nextcloud -d nextcloud -c "SELECT pg_size_pretty(pg_database_size('nextcloud'));"
```

### Collabora Sorunları

```bash
# Collabora health check
curl -s http://localhost:9980/hosting/capabilities

# WOPI protokol test
docker exec -u www-data nextcloud php occ richdocuments:activate-config
```

## 🔐 Güvenlik

- ✅ TLS 1.3 ile HTTPS (NPM)
- ✅ Fail2ban brute-force koruması
- ✅ Firewalld yapılandırması
- ✅ SELinux desteği
- ✅ 2FA desteği
- ✅ Redis şifreli bağlantı
- ✅ PostgreSQL şifreli bağlantı

## 💾 Yedekleme

```bash
# Manuel yedek al
./scripts/backup.sh

# Veritabanı yedeği
docker exec postgres pg_dump -U nextcloud nextcloud > backup.sql

# Veritabanını geri yükle
cat backup.sql | docker exec -i postgres psql -U nextcloud -d nextcloud
```

## 📞 Destek ve Kaynaklar

- [Nextcloud Dokümantasyonu](https://docs.nextcloud.com/)
- [Collabora Online Dokümantasyonu](https://www.collaboraoffice.com/code/)
- [TrueNAS Dokümantasyonu](https://www.truenas.com/docs/)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)

---

**Versiyon:** 2.0.0  
**Son Güncelleme:** Ocak 2026  
**Platform:** AlmaLinux 10 + Docker  
**Desteklenen Nextcloud:** v32 (stable-fpm)
