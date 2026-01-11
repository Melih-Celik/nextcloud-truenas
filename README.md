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

### WOPI Protokolü

Collabora ve Nextcloud arasındaki iletişim WOPI (Web Application Open Platform Interface) protokolü üzerinden gerçekleşir:

```
┌─────────────────┐         WOPI          ┌─────────────────┐
│                 │ ◄──────────────────── │                 │
│    Nextcloud    │   (dosya erişimi)     │    Collabora    │
│  cloud.x.com    │ ────────────────────► │  office.x.com   │
│                 │    (düzenleme UI)     │                 │
└─────────────────┘                       └─────────────────┘
         │                                         │
         └──────────────┬──────────────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │   NPM (SSL)     │
              │   :80, :443     │
              └─────────────────┘
                        │
                        ▼
                    İNTERNET
```

### Collabora Yapılandırması

#### 1. Environment Değişkenleri (.env)

```bash
# Collabora'nın public URL'i (NPM üzerinden)
COLLABORA_SERVER_NAME=office.yourdomain.com

# Nextcloud'un public URL'i (WOPI istekleri için)
# Port numarası dahil edilmeli (HTTPS=443, HTTP=80)
COLLABORA_WOPI_URL=https://cloud.yourdomain.com:443

# Admin panel credentials
COLLABORA_ADMIN_USER=admin
COLLABORA_ADMIN_PASSWORD=güçlü-şifre
```

#### 2. Nextcloud'da Aktifleştirme

1. **Nextcloud Office uygulamasını kur:**
   - Ayarlar → Uygulamalar → Office & text → "Nextcloud Office" yükle

2. **Collabora sunucusunu yapılandır:**
   - Ayarlar → Yönetim → Nextcloud Office
   - "Use your own server" seç
   - URL: `https://office.yourdomain.com`
   - ✅ Disable certificate verification (self-signed için)

3. **WOPI allowlist kontrolü (opsiyonel):**
   ```bash
   docker exec -u www-data nextcloud php occ config:app:get richdocuments wopi_allowlist
   ```

#### 3. NPM Proxy Host (Collabora için)

1. **Hosts → Proxy Hosts → Add Proxy Host**
2. **Details sekmesi:**
   - Domain Names: `office.yourdomain.com`
   - Scheme: `http`
   - Forward Hostname / IP: `collabora`
   - Forward Port: `9980`
   - ✓ **Websockets Support** (zorunlu!)
3. **SSL sekmesi:**
   - SSL Certificate: Request a new SSL Certificate
   - ✓ Force SSL
   - ✓ HTTP/2 Support
4. **Advanced sekmesi:**
   ```nginx
   # Collabora WOPI için gerekli header'lar
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header X-Forwarded-Proto $scheme;
   
   # WebSocket desteği (zorunlu)
   proxy_http_version 1.1;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   
   # Timeout (uzun süren düzenlemeler için)
   proxy_connect_timeout 3600;
   proxy_send_timeout 3600;
   proxy_read_timeout 3600;
   ```

### Collabora Yönetimi

```bash
# Collabora loglarını izle
docker compose -f docker-compose.yml -f docker-compose.collabora.yml logs -f collabora

# Collabora'yı yeniden başlat
docker compose -f docker-compose.yml -f docker-compose.collabora.yml restart collabora

# WOPI discovery endpoint kontrolü
curl -s http://localhost:9980/hosting/discovery | head -50

# Collabora capabilities kontrolü
curl -s http://localhost:9980/hosting/capabilities

# Collabora admin paneli
# URL: https://office.yourdomain.com/browser/dist/admin/admin.html
# Kullanıcı/Şifre: .env dosyasında COLLABORA_ADMIN_USER ve COLLABORA_ADMIN_PASSWORD
```

### Collabora Sorun Giderme

#### "WOPI host did not respond"

1. **WOPI URL kontrolü:**
   ```bash
   # .env dosyasında COLLABORA_WOPI_URL doğru mu?
   # Nextcloud'un public URL'i olmalı
   grep COLLABORA_WOPI_URL /opt/nextcloud/.env
   ```

2. **Collabora'dan Nextcloud'a erişim testi:**
   ```bash
   docker exec collabora curl -I https://cloud.yourdomain.com
   ```

3. **aliasgroup ayarını kontrol et:**
   ```bash
   docker logs collabora 2>&1 | grep -i alias
   ```

#### "Discovery endpoint not responding"

```bash
# Collabora health check
curl -v http://localhost:9980/hosting/discovery

# Container içinden test
docker exec collabora curl -f http://localhost:9980/hosting/discovery
```

#### Doküman açılmıyor

1. **WebSocket bağlantısını kontrol et:**
   - NPM'de "Websockets Support" aktif mi?
   - Tarayıcı konsolu'nda WebSocket hataları var mı?

2. **SSL sertifikasını kontrol et:**
   ```bash
   curl -v https://office.yourdomain.com/hosting/capabilities
   ```

## 🔐 Nginx Proxy Manager (SSL)

NPM, Let's Encrypt sertifikalarını otomatik yönetir ve SSL terminasyonu sağlar.

### NPM İlk Kurulum

1. **Admin paneline eriş:** `http://SUNUCU_IP:81`
2. **Varsayılan giriş:**
   - Email: `admin@example.com`
   - Şifre: `changeme`
3. **Şifreyi değiştir** (ilk girişte zorunlu)

### Nextcloud için Proxy Host Ekleme

1. **Hosts → Proxy Hosts → Add Proxy Host**
2. **Details sekmesi:**
   - Domain Names: `cloud.yourdomain.com`
   - Scheme: `http`
   - Forward Hostname / IP: `nginx`
   - Forward Port: `80`
   - ✓ Cache Assets
   - ✓ Block Common Exploits
   - ✓ Websockets Support
3. **SSL sekmesi:**
   - SSL Certificate: Request a new SSL Certificate
   - ✓ Force SSL
   - ✓ HTTP/2 Support
   - ✓ HSTS Enabled
   - Email: SSL bildirimleri için email
4. **Advanced sekmesi (ÖNEMLİ):**
   ```nginx
   # Gerçek IP adresi iletimi (brute-force koruması için gerekli)
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header X-Forwarded-Proto $scheme;
   
   # Büyük dosya yüklemeleri için
   client_max_body_size 16G;
   proxy_request_buffering off;
   
   # Timeout ayarları (büyük dosya transferleri için)
   proxy_connect_timeout 3600;
   proxy_send_timeout 3600;
   proxy_read_timeout 3600;
   
   # WebDAV desteği
   proxy_buffering off;
   ```

### Collabora için Proxy Host Ekleme

1. **Hosts → Proxy Hosts → Add Proxy Host**
2. **Details sekmesi:**
   - Domain Names: `office.yourdomain.com`
   - Scheme: `http`
   - Forward Hostname / IP: `collabora`
   - Forward Port: `9980`
   - ✓ Websockets Support (zorunlu!)
3. **SSL sekmesi:**
   - SSL Certificate: Request a new SSL Certificate
   - ✓ Force SSL
   - ✓ HTTP/2 Support
4. **Advanced sekmesi:**
   ```nginx
   # Collabora için gerekli header'lar
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header X-Forwarded-Proto $scheme;
   
   # WebSocket desteği (zorunlu)
   proxy_http_version 1.1;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   
   # Timeout ayarları
   proxy_connect_timeout 3600;
   proxy_send_timeout 3600;
   proxy_read_timeout 3600;
   ```

### NPM Sonrası Nextcloud Yapılandırması

NPM üzerinden gerçek IP adreslerinin Nextcloud'a iletilmesi için `config.php` dosyasına şu ayarları ekleyin:

```bash
# Trusted proxies ekle (Docker network aralıkları)
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 0 --value="172.20.0.0/16"
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 1 --value="10.0.0.0/8"
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 2 --value="192.168.0.0/16"
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 3 --value="172.16.0.0/12"

# Forwarded for headers ayarla (gerçek IP algılama için)
docker exec -u www-data nextcloud php occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR"
docker exec -u www-data nextcloud php occ config:system:set forwarded_for_headers 1 --value="HTTP_X_REAL_IP"

# HTTPS zorlaması
docker exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="https"
docker exec -u www-data nextcloud php occ config:system:set overwrite.cli.url --value="https://cloud.yourdomain.com"
```

> ⚠️ **Önemli:** Bu ayarlar yapılmazsa, tüm istekler proxy IP'sinden geliyor gibi görünür ve brute-force koruması yanlış çalışarak "multiple invalid login attempts" hatası verir.

### Brute-Force Throttle Temizleme

Eğer IP'niz yanlışlıkla engellendiyse:

```bash
# Belirli bir IP'yi temizle
docker exec -u www-data nextcloud php occ security:bruteforce:reset SENIN_IP_ADRESIN

# Tüm engelleri temizle
docker exec -u www-data nextcloud php occ security:bruteforce:reset all
```

### NPM Yönetimi

```bash
# NPM loglarını izle
docker compose -f docker-compose.yml -f docker-compose.npm.yml logs -f npm

# NPM'i yeniden başlat
docker compose -f docker-compose.yml -f docker-compose.npm.yml restart npm
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
