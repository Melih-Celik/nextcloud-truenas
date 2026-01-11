# Bakım ve Operasyon Rehberi

Bu döküman, Nextcloud + TrueNAS sisteminin günlük bakım ve operasyon prosedürlerini anlatmaktadır.

## 1️⃣ Günlük Operasyonlar

### 1.1 Sistem Durumu Kontrolü

```bash
# Health check scripti çalıştır
./scripts/health-check.sh

# Docker container durumu
docker compose ps

# Disk kullanımı
df -h
df -h /mnt/nextcloud-data

# NFS mount durumu
mount | grep nfs
```

### 1.2 Log Kontrolü

```bash
# Nextcloud logları
docker compose logs --tail=100 nextcloud

# Tüm servis logları
docker compose logs --tail=50

# Hata logları
docker compose logs --tail=100 | grep -i error

# Nextcloud uygulama logu
tail -f /mnt/nextcloud-data/nextcloud.log | jq .
```

### 1.3 Aktif Kullanıcıları Görüntüleme

```bash
# Aktif sessionlar
docker exec -u www-data nextcloud php occ user:list

# Online kullanıcılar (serverinfo app gerekli)
docker exec -u www-data nextcloud php occ serverinfo:update
```

## 2️⃣ Haftalık Bakım

### 2.1 Veritabanı Bakımı

```bash
# PostgreSQL VACUUM
docker exec postgres psql -U nextcloud -d nextcloud -c "VACUUM ANALYZE;"

# Dead tuple kontrolü
docker exec postgres psql -U nextcloud -d nextcloud -c "
SELECT relname, n_dead_tup 
FROM pg_stat_user_tables 
WHERE n_dead_tup > 1000 
ORDER BY n_dead_tup DESC;
"
```

### 2.2 ZFS Bakımı

```bash
# Pool durumu
zpool status storage

# Scrub başlat (Pazar gece önerilir)
zpool scrub storage

# Scrub durumunu kontrol et
zpool status storage | grep scan
```

### 2.3 Nextcloud Bakımı

```bash
# Eksik indeksleri ekle
docker exec -u www-data nextcloud php occ db:add-missing-indices

# Dosya taraması
docker exec -u www-data nextcloud php occ files:scan --all

# Çöp kutusunu temizle (30 günden eski)
docker exec -u www-data nextcloud php occ trashbin:cleanup --all
```

## 3️⃣ Aylık Bakım

### 3.1 Güncelleme Prosedürü

```bash
# 1. Yedek al
./scripts/backup.sh

# 2. Maintenance mode aktif
docker exec -u www-data nextcloud php occ maintenance:mode --on

# 3. Docker images güncelle
docker compose pull

# 4. Container'ları yeniden başlat
docker compose up -d

# 5. Veritabanı migration
docker exec -u www-data nextcloud php occ upgrade

# 6. Maintenance mode kapat
docker exec -u www-data nextcloud php occ maintenance:mode --off

# 7. Durumu kontrol et
docker exec -u www-data nextcloud php occ status
```

### 3.2 SSL Sertifika Kontrolü

```bash
# Sertifika bitiş tarihi
openssl x509 -enddate -noout -in /opt/nextcloud/ssl/fullchain.pem

# Let's Encrypt yenileme
sudo certbot renew

# Sertifikaları kopyala
sudo cp /etc/letsencrypt/live/cloud.yourdomain.com/*.pem /opt/nextcloud/ssl/

# Nginx restart
docker compose restart nginx
```

### 3.3 Veritabanı Reindex

```bash
docker exec postgres psql -U nextcloud -d nextcloud -c "REINDEX DATABASE nextcloud;"
```

### 3.4 Eski Verileri Temizle

```bash
# Eski versiyonları temizle
docker exec -u www-data nextcloud php occ versions:cleanup

# Eski activity loglarını temizle
docker exec -u www-data nextcloud php occ activity:cleanup

# Eski preview'ları temizle
docker exec -u www-data nextcloud php occ preview:repair
```

## 4️⃣ Yedekleme Prosedürleri

### 4.1 Otomatik Yedekleme Kurulumu

```bash
# Günlük yedekleme (gece 02:00)
sudo crontab -e

# Ekle:
0 2 * * * /opt/nextcloud/scripts/backup.sh >> /var/log/nextcloud-backup.log 2>&1
```

### 4.2 Manuel Yedekleme

```bash
# Tam yedekleme
./scripts/backup.sh

# Sadece veritabanı
docker exec postgres pg_dump -U nextcloud nextcloud > backup_db_$(date +%Y%m%d).sql
```

### 4.3 ZFS Snapshot

```bash
# TrueNAS üzerinde (SSH ile)
ssh admin@192.168.1.20 "zfs snapshot -r storage/nextcloud@manual-$(date +%Y%m%d)"

# Snapshot listesi
ssh admin@192.168.1.20 "zfs list -t snapshot -r storage/nextcloud"
```

### 4.4 Yedekten Geri Yükleme

```bash
# 1. Maintenance mode
docker exec -u www-data nextcloud php occ maintenance:mode --on

# 2. Container'ları durdur
docker compose stop

# 3. Veritabanını geri yükle
gunzip -c backup_db_YYYYMMDD.sql.gz | docker exec -i postgres psql -U nextcloud -d nextcloud

# 4. ZFS snapshot'tan geri yükle (TrueNAS üzerinde)
ssh admin@192.168.1.20 "zfs rollback storage/nextcloud/data@snapshot-name"

# 5. Container'ları başlat
docker compose start

# 6. Maintenance mode kapat
docker exec -u www-data nextcloud php occ maintenance:mode --off
```

## 5️⃣ Sorun Giderme

### 5.1 Sık Karşılaşılan Sorunlar

#### NFS Mount Hatası

```bash
# Hata kontrol
dmesg | grep nfs
mount | grep nfs

# NFS servisini kontrol et (TrueNAS)
showmount -e 192.168.1.20

# Yeniden mount
sudo umount /mnt/nextcloud-data
sudo mount -a

# fstab kontrolü
cat /etc/fstab | grep nextcloud
```

#### Veritabanı Bağlantı Hatası

```bash
# PostgreSQL durumu
docker exec postgres pg_isready -U nextcloud

# Connection count
docker exec postgres psql -U nextcloud -d nextcloud -c "SELECT count(*) FROM pg_stat_activity;"

# Restart
docker compose restart postgres
```

#### Redis Bağlantı Hatası

```bash
# Redis ping
docker exec redis redis-cli -a $REDIS_PASSWORD ping

# Memory durumu
docker exec redis redis-cli -a $REDIS_PASSWORD info memory

# Cache temizle
docker exec redis redis-cli -a $REDIS_PASSWORD flushall
```

#### Dosya Kilidi Sorunu

```bash
# Kilitleri listele
docker exec -u www-data nextcloud php occ files:scan --all

# Tüm kilitleri temizle (dikkatli kullanın)
docker exec -u www-data nextcloud php occ files:scan --repair

# Redis lock temizle
docker exec redis redis-cli -a $REDIS_PASSWORD keys "lock_*" | xargs docker exec redis redis-cli -a $REDIS_PASSWORD del
```

#### Yavaş Performans

```bash
# ARC hit rate kontrol (TrueNAS)
arc_summary | grep "ARC Hit"

# NFS latency
nfsiostat 1

# Disk I/O
iotop -o

# PHP memory
docker stats nextcloud
```

### 5.2 Log Analizi

```bash
# Hata sayısı
grep -c "error" /mnt/nextcloud-data/nextcloud.log

# Son hatalar
tail -100 /mnt/nextcloud-data/nextcloud.log | jq 'select(.level >= 3)'

# Login başarısızlıkları
grep "Login failed" /mnt/nextcloud-data/nextcloud.log | tail -20
```

### 5.3 Emergency Prosedürleri

#### Acil Maintenance Mode

```bash
# Dosya ile maintenance mode (occ çalışmazsa)
touch /mnt/nextcloud-config/maintenance.on

# Kapatmak için
rm /mnt/nextcloud-config/maintenance.on
```

#### Container Recovery

```bash
# Container'ı yeniden oluştur
docker compose up -d --force-recreate nextcloud

# Volume'ları koruyarak tamamen yeniden başlat
docker compose down
docker compose up -d
```

## 6️⃣ Monitoring Kurulumu

### 6.1 Prometheus + Grafana (Opsiyonel)

```yaml
# monitoring/docker-compose.yml
version: '3'
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
  
  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  grafana-data:
```

### 6.2 Uptime Monitoring

```bash
# Basit health check scripti cron'da
*/5 * * * * curl -s -o /dev/null -w "%{http_code}" https://cloud.yourdomain.com/status.php | grep -q 200 || echo "Nextcloud DOWN" | mail -s "Alert" admin@example.com
```

## 7️⃣ Kullanıcı Yönetimi

### 7.1 Kullanıcı İşlemleri

```bash
# Kullanıcı listesi
docker exec -u www-data nextcloud php occ user:list

# Kullanıcı ekle
docker exec -u www-data nextcloud php occ user:add --display-name="Ahmet Yılmaz" ahmet

# Şifre sıfırla
docker exec -u www-data nextcloud php occ user:resetpassword ahmet

# Kullanıcı deaktif et
docker exec -u www-data nextcloud php occ user:disable ahmet

# Kullanıcı sil
docker exec -u www-data nextcloud php occ user:delete ahmet

# Grup oluştur
docker exec -u www-data nextcloud php occ group:add "Muhasebe"

# Kullanıcıyı gruba ekle
docker exec -u www-data nextcloud php occ group:adduser "Muhasebe" ahmet
```

### 7.2 Kota Yönetimi

```bash
# Varsayılan kota ayarla
docker exec -u www-data nextcloud php occ config:app:set files default_quota --value="100 GB"

# Kullanıcıya özel kota
docker exec -u www-data nextcloud php occ user:setting ahmet files quota "500 GB"

# Kota kullanımını görüntüle
docker exec -u www-data nextcloud php occ user:info ahmet
```

## 8️⃣ Ölçeklendirme

### 8.1 Dikey Ölçeklendirme

1. **Daha fazla RAM:** ZFS ARC ve PostgreSQL cache için
2. **Daha fazla CPU:** PHP-FPM worker sayısını artır
3. **Daha hızlı SSD:** L2ARC ve SLOG için

### 8.2 Yatay Ölçeklendirme

1. **Birden fazla Nextcloud instance:** Load balancer arkasında
2. **Read replica:** PostgreSQL streaming replication
3. **Redis Cluster:** Dağıtılmış cache

## ✅ Bakım Takvimi

### Günlük
- [ ] Health check
- [ ] Log kontrolü
- [ ] Backup doğrulama

### Haftalık
- [ ] ZFS scrub (Pazar)
- [ ] PostgreSQL VACUUM
- [ ] Disk kullanım raporu
- [ ] Fail2ban raporu

### Aylık
- [ ] Güncelleme kontrolü
- [ ] SSL sertifika kontrolü
- [ ] Veritabanı reindex
- [ ] Eski dosya temizliği
- [ ] Performans analizi

### Yıllık
- [ ] Full disaster recovery testi
- [ ] Güvenlik audit
- [ ] Kapasite planlaması
- [ ] SLA gözden geçirme
