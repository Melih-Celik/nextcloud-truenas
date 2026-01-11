# Performans Tuning Rehberi

Bu döküman, 60TB Nextcloud + TrueNAS sisteminin performans optimizasyonunu anlatmaktadır.

## 📊 Performans Hedefleri

| Metrik | Hedef |
|--------|-------|
| Sayfa yükleme | < 2 saniye |
| Dosya listesi | < 1 saniye |
| Upload (1GB) | < 60 saniye (1Gbps NIC) |
| Download (1GB) | < 60 saniye (1Gbps NIC) |
| Eşzamanlı kullanıcı | 50+ |

## 1️⃣ TrueNAS / ZFS Optimizasyonu

### 1.1 ARC (Adaptive Replacement Cache)

ZFS ARC, RAM'de dosya ve metadata cache'i tutar. 60TB storage için kritik öneme sahiptir.

```bash
# Mevcut ARC durumunu görüntüle
arc_summary

# veya
cat /proc/spl/kstat/zfs/arcstats
```

#### ARC Boyutu Ayarlama

```bash
# /etc/modprobe.d/zfs.conf
# 64GB RAM için 48GB ARC
options zfs zfs_arc_max=51539607552

# 32GB RAM için 24GB ARC
options zfs zfs_arc_max=25769803776

# Uygula
update-initramfs -u
reboot
```

#### Önerilen ARC Boyutları

| Toplam RAM | Önerilen ARC Max |
|------------|------------------|
| 32 GB | 24 GB |
| 64 GB | 48 GB |
| 128 GB | 96 GB |

### 1.2 L2ARC (Level 2 ARC)

SSD üzerinde ikinci seviye cache. Sıcak veriler için idealdir.

```bash
# L2ARC SSD ekle
zpool add storage cache /dev/nvme0n1

# L2ARC ayarları
echo "options zfs l2arc_write_max=536870912" >> /etc/modprobe.d/zfs.conf  # 512MB/s
echo "options zfs l2arc_headroom=12" >> /etc/modprobe.d/zfs.conf
echo "options zfs l2arc_noprefetch=0" >> /etc/modprobe.d/zfs.conf
```

### 1.3 SLOG (ZFS Intent Log)

Sync write performansını artırır. NFS için önemlidir.

```bash
# SLOG SSD ekle (mirror önerilir)
zpool add storage log mirror /dev/nvme1n1 /dev/nvme1n2

# Durumu kontrol et
zpool status storage
```

### 1.4 Dataset Optimizasyonu

```bash
# Büyük dosyalar için (video, ISO, backup)
zfs set recordsize=1M storage/nextcloud/data

# Veritabanı için (eğer TrueNAS üzerinde olsaydı)
zfs set recordsize=16K storage/nextcloud/database
zfs set primarycache=metadata storage/nextcloud/database
zfs set logbias=throughput storage/nextcloud/database

# Compression (CPU'yu az kullanır, I/O azaltır)
zfs set compression=lz4 storage/nextcloud

# atime kapatma (her okumada metadata güncellenmez)
zfs set atime=off storage/nextcloud

# Extended attributes
zfs set xattr=sa storage/nextcloud
zfs set acltype=posixacl storage/nextcloud
```

### 1.5 ZFS Scrub Optimizasyonu

```bash
# Scrub I/O limitini ayarla (production'da)
echo 100 > /sys/module/zfs/parameters/zfs_scrub_delay

# Scrub başlat (haftalık cron önerilir)
zpool scrub storage
```

## 2️⃣ NFS Performans Optimizasyonu

### 2.1 TrueNAS NFS Ayarları

```yaml
# TrueNAS UI → Services → NFS → Configure
Number of servers: 16
Enable NFSv4: Yes
NFSv4 Domain: localdomain
```

### 2.2 Client Mount Seçenekleri

```bash
# /etc/fstab (Nextcloud sunucusu)
192.168.1.20:/mnt/storage/nextcloud/data /mnt/nextcloud-data nfs4 \
    rw,hard,intr,\
    rsize=1048576,\
    wsize=1048576,\
    timeo=600,\
    retrans=2,\
    nconnect=8,\
    _netdev 0 0
```

| Seçenek | Değer | Açıklama |
|---------|-------|----------|
| rsize | 1048576 | 1MB read buffer |
| wsize | 1048576 | 1MB write buffer |
| nconnect | 8 | Paralel TCP bağlantısı (Linux 5.3+) |
| timeo | 600 | 60 saniye timeout |

### 2.3 NFS Tuning (Client)

```bash
# /etc/sysctl.d/99-nfs-performance.conf
# NFS client tuning
sunrpc.tcp_slot_table_entries = 128
sunrpc.udp_slot_table_entries = 128

# Network buffers
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Uygula
sysctl -p /etc/sysctl.d/99-nfs-performance.conf
```

## 3️⃣ PostgreSQL Optimizasyonu

### 3.1 docker-compose.yml Ayarları

```yaml
postgres:
  command: >
    postgres
    -c shared_buffers=1GB
    -c effective_cache_size=3GB
    -c work_mem=128MB
    -c maintenance_work_mem=512MB
    -c checkpoint_completion_target=0.9
    -c wal_buffers=64MB
    -c default_statistics_target=100
    -c random_page_cost=1.1
    -c effective_io_concurrency=200
    -c min_wal_size=1GB
    -c max_wal_size=4GB
    -c max_connections=100
    -c log_min_duration_statement=1000
```

### 3.2 Bellek Hesaplama

| Parametre | Formül | 16GB Server |
|-----------|--------|-------------|
| shared_buffers | RAM × 0.25 | 4 GB |
| effective_cache_size | RAM × 0.75 | 12 GB |
| work_mem | RAM / max_connections / 4 | 40 MB |
| maintenance_work_mem | RAM × 0.05 | 800 MB |

### 3.3 Veritabanı Bakımı

```bash
# VACUUM ve ANALYZE (haftalık)
docker exec postgres psql -U nextcloud -d nextcloud -c "VACUUM ANALYZE;"

# Reindex (aylık)
docker exec postgres psql -U nextcloud -d nextcloud -c "REINDEX DATABASE nextcloud;"

# İstatistikleri görüntüle
docker exec postgres psql -U nextcloud -d nextcloud -c "
SELECT 
    relname as table,
    n_live_tup as rows,
    n_dead_tup as dead_rows,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables 
ORDER BY n_dead_tup DESC 
LIMIT 10;
"
```

## 4️⃣ Redis Optimizasyonu

### 4.1 Redis Yapılandırması

```conf
# /opt/nextcloud/configs/redis/redis.conf

# Bellek limiti
maxmemory 1gb
maxmemory-policy allkeys-lru

# Persistence (cache için AOF yeterli)
appendonly yes
appendfsync everysec
save ""

# Network
tcp-keepalive 300
timeout 0
tcp-backlog 511

# Performance
activerehashing yes
hz 10
```

### 4.2 Redis Monitoring

```bash
# Bağlantı testi
docker exec redis redis-cli -a $REDIS_PASSWORD ping

# Memory durumu
docker exec redis redis-cli -a $REDIS_PASSWORD info memory

# Hit rate (yüksek olmalı)
docker exec redis redis-cli -a $REDIS_PASSWORD info stats | grep keyspace
```

## 5️⃣ PHP-FPM Optimizasyonu

### 5.1 Process Manager Ayarları

```ini
# /opt/nextcloud/configs/php/custom.ini

; Process management
pm = dynamic
pm.max_children = 120
pm.start_servers = 12
pm.min_spare_servers = 6
pm.max_spare_servers = 18
pm.max_requests = 500
pm.process_idle_timeout = 10s
```

#### pm.max_children Hesaplama

```bash
# Formül: (Toplam RAM - Diğer servisler) / PHP process başına RAM
# Örnek: (16GB - 4GB) / 100MB = 120

# PHP process başına ortalama RAM
docker stats --no-stream nextcloud | awk '{print $4}'
```

### 5.2 OPcache Ayarları

```ini
; OPcache (compiled PHP cache)
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=10000
opcache.revalidate_freq=60
opcache.save_comments=1
opcache.jit=1255
opcache.jit_buffer_size=128M
```

### 5.3 Upload/Download Limitleri

```ini
; Large file support (60TB storage için)
upload_max_filesize = 16G
post_max_size = 16G
max_input_time = 3600
max_execution_time = 3600
memory_limit = 1024M
```

## 6️⃣ Nextcloud Optimizasyonu

### 6.1 config.php Performans Ayarları

```php
<?php
$CONFIG = array (
  // Cache
  'memcache.local' => '\\OC\\Memcache\\APCu',
  'memcache.distributed' => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  
  // Filesystem - ÖNEMLİ!
  'filesystem_check_changes' => 0,  // Değişiklik kontrolünü kapat
  'filelocking.enabled' => true,
  
  // Preview
  'preview_max_x' => 2048,
  'preview_max_y' => 2048,
  'preview_max_filesize_image' => 50,
  
  // Trashbin
  'trashbin_retention_obligation' => 'auto, 30',
  
  // Versions
  'versions_retention_obligation' => 'auto, 365',
);
```

### 6.2 Background Jobs (Cron)

```bash
# Cron moduna geç (AJAX yerine)
docker exec -u www-data nextcloud php occ background:cron

# Crontab (her 5 dakika)
*/5 * * * * docker exec -u www-data nextcloud php cron.php
```

### 6.3 Dosya İndeksleme Optimizasyonu

```bash
# Full scan (ilk kurulum sonrası)
docker exec -u www-data nextcloud php occ files:scan --all

# Tek kullanıcı için scan
docker exec -u www-data nextcloud php occ files:scan admin

# Paralel scan (daha hızlı)
docker exec -u www-data nextcloud php occ files:scan --all -v --unscanned

# Eksik indeksleri ekle
docker exec -u www-data nextcloud php occ db:add-missing-indices

# Bigint dönüşümü (büyük dosya sistemleri için gerekli)
docker exec -u www-data nextcloud php occ db:convert-filecache-bigint
```

### 6.4 Preview Generation

```bash
# Preview Generator app kur
docker exec -u www-data nextcloud php occ app:enable previewgenerator

# Pre-generate (gece çalıştır)
docker exec -u www-data nextcloud php occ preview:pre-generate

# Crontab
0 2 * * * docker exec -u www-data nextcloud php occ preview:pre-generate
```

## 7️⃣ Nginx Optimizasyonu

### 7.1 Worker ve Connection Ayarları

```nginx
# nginx.conf
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}
```

### 7.2 Buffer ve Timeout Ayarları

```nginx
http {
    # Buffers
    client_body_buffer_size 512k;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 32k;
    
    # File handling
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    
    # Keepalive
    keepalive_timeout 65;
    keepalive_requests 1000;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
}
```

## 8️⃣ Linux Kernel Tuning

### 8.1 Sysctl Ayarları

```bash
# /etc/sysctl.d/99-nextcloud-performance.conf

# Network
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# TCP
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# File system
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

# Virtual memory
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
vm.vfs_cache_pressure = 50

# Uygula
sysctl -p /etc/sysctl.d/99-nextcloud-performance.conf
```

### 8.2 Limits

```bash
# /etc/security/limits.d/99-nextcloud.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
```

## 9️⃣ Monitoring ve Benchmarking

### 9.1 Performans Monitoring

```bash
# Sistem kaynakları
htop
iotop
nload

# NFS performansı
nfsstat -c
nfsiostat 1

# Docker stats
docker stats

# ZFS ARC
arc_summary
```

### 9.2 Benchmark Araçları

```bash
# Disk I/O testi
fio --name=random-write --ioengine=posixaio --rw=randwrite \
    --bs=4k --numjobs=4 --size=1g --runtime=60 \
    --directory=/mnt/nextcloud-data

# Network throughput
iperf3 -s  # TrueNAS
iperf3 -c 192.168.1.20 -t 30  # Nextcloud

# HTTP benchmark
ab -n 1000 -c 50 https://cloud.yourdomain.com/status.php
```

### 9.3 Nextcloud Benchmark

```bash
# Serverinfo app
docker exec -u www-data nextcloud php occ serverinfo:update

# Aktif bağlantılar
docker exec -u www-data nextcloud php occ user:list | wc -l
```

## 📋 Performans Checklist

### ZFS/TrueNAS
- [ ] ARC boyutu ayarlandı
- [ ] L2ARC SSD eklendi
- [ ] SLOG SSD eklendi
- [ ] Dataset recordsize optimizasyonu
- [ ] Compression aktif (lz4)
- [ ] atime kapalı

### NFS
- [ ] rsize/wsize 1M
- [ ] nconnect=8 (Linux 5.3+)
- [ ] Sunrpc slot table artırıldı

### Veritabanı
- [ ] PostgreSQL memory tuning
- [ ] Regular VACUUM
- [ ] Index optimizasyonu

### Cache
- [ ] Redis yapılandırıldı
- [ ] APCu aktif
- [ ] OPcache JIT aktif

### Nextcloud
- [ ] filesystem_check_changes=0
- [ ] Cron mode aktif
- [ ] Bigint migration tamamlandı
- [ ] Missing indices eklendi
- [ ] Preview pre-generation aktif

### Sistem
- [ ] Kernel tuning uygulandı
- [ ] File limits artırıldı
- [ ] Network buffers optimizasyonu
