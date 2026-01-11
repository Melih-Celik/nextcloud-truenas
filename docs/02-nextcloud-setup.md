# Nextcloud Sunucusu Kurulum Rehberi

Bu döküman, Docker üzerinde Nextcloud kurulumunu ve TrueNAS NFS entegrasyonunu anlatmaktadır.

## 📋 Ön Gereksinimler

- Ubuntu 24.04 LTS Server
- Minimum 8GB RAM, 4 CPU Core
- 64GB+ SSD (OS ve Docker için)
- TrueNAS NFS paylaşımları hazır
- Domain adı ve SSL sertifikası (production için)

## 1️⃣ Ubuntu Server Kurulumu

### 1.1 Minimal Kurulum

1. Ubuntu 24.04 LTS Server ISO'yu indirin
2. Minimal installation seçin
3. OpenSSH server'ı kurun
4. Statik IP yapılandırın

### 1.2 Temel Yapılandırma

```bash
# Sistemi güncelle
sudo apt update && sudo apt upgrade -y

# Gerekli paketleri kur
sudo apt install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    nfs-common \
    ca-certificates \
    gnupg \
    lsb-release \
    ufw

# Timezone ayarla
sudo timedatectl set-timezone Europe/Istanbul

# Hostname ayarla
sudo hostnamectl set-hostname nextcloud-server
```

### 1.3 Statik IP (Netplan)

```bash
sudo vim /etc/netplan/00-installer-config.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp0s3:  # Interface adınıza göre değiştirin
      dhcp4: false
      addresses:
        - 192.168.1.10/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

```bash
sudo netplan apply
```

## 2️⃣ Docker Kurulumu

### 2.1 Docker Engine

```bash
# Docker GPG key ekle
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Repository ekle
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Docker kur
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Kullanıcıyı docker grubuna ekle
sudo usermod -aG docker $USER
newgrp docker

# Docker'ı başlat
sudo systemctl enable docker
sudo systemctl start docker
```

### 2.2 Doğrulama

```bash
docker --version
docker compose version
```

## 3️⃣ NFS Mount Yapılandırması

### 3.1 Mount Noktaları Oluştur

```bash
# Mount dizinlerini oluştur
sudo mkdir -p /mnt/nextcloud-data
sudo mkdir -p /mnt/nextcloud-config
```

### 3.2 NFS Mount Test

```bash
# TrueNAS'tan export listesini kontrol et
showmount -e 192.168.1.20

# Manuel mount test
sudo mount -t nfs4 192.168.1.20:/mnt/storage/nextcloud/data /mnt/nextcloud-data
sudo mount -t nfs4 192.168.1.20:/mnt/storage/nextcloud/config /mnt/nextcloud-config

# Yazma testi
sudo touch /mnt/nextcloud-data/test.txt
ls -la /mnt/nextcloud-data/

# Test dosyasını sil
sudo rm /mnt/nextcloud-data/test.txt

# Unmount (fstab için)
sudo umount /mnt/nextcloud-data
sudo umount /mnt/nextcloud-config
```

### 3.3 Kalıcı Mount (fstab)

```bash
sudo vim /etc/fstab
```

Ekleyin:
```fstab
# Nextcloud NFS Mounts
192.168.1.20:/mnt/storage/nextcloud/data    /mnt/nextcloud-data    nfs4    rw,hard,intr,rsize=1048576,wsize=1048576,timeo=600,retrans=2,_netdev    0    0
192.168.1.20:/mnt/storage/nextcloud/config  /mnt/nextcloud-config  nfs4    rw,hard,intr,rsize=1048576,wsize=1048576,timeo=600,retrans=2,_netdev    0    0
```

```bash
# Mount et
sudo mount -a

# Doğrula
df -h | grep nextcloud
```

### 3.4 NFS Mount Seçenekleri Açıklaması

| Seçenek | Açıklama |
|---------|----------|
| `rw` | Read-write erişim |
| `hard` | Sunucu yanıt vermezse süresiz bekle |
| `intr` | Kesintiye izin ver (Ctrl+C) |
| `rsize=1048576` | 1MB okuma buffer (performans) |
| `wsize=1048576` | 1MB yazma buffer (performans) |
| `timeo=600` | 60 saniye timeout |
| `retrans=2` | 2 retry |
| `_netdev` | Network hazır olana kadar bekle |

## 4️⃣ Proje Dizini Hazırlığı

```bash
# Proje dizini
sudo mkdir -p /opt/nextcloud
cd /opt/nextcloud

# Gerekli dizinleri oluştur
mkdir -p configs/nginx
mkdir -p configs/php
mkdir -p configs/redis
mkdir -p db-data
mkdir -p redis-data

# İzinleri ayarla
sudo chown -R $USER:$USER /opt/nextcloud
```

## 5️⃣ Docker Compose ile Deployment

### 5.1 Dosyaları Kopyala

Repository'den dosyaları `/opt/nextcloud` dizinine kopyalayın:

```bash
# Git clone veya manuel kopyalama
cp docker/docker-compose.yml /opt/nextcloud/
cp docker/.env.example /opt/nextcloud/.env
cp -r docker/configs/* /opt/nextcloud/configs/
```

### 5.2 Environment Dosyasını Düzenle

```bash
vim /opt/nextcloud/.env
```

Zorunlu değişiklikleri yapın:
- `NEXTCLOUD_ADMIN_PASSWORD`
- `POSTGRES_PASSWORD`
- `REDIS_PASSWORD`
- `NEXTCLOUD_TRUSTED_DOMAINS`

### 5.3 Başlat

```bash
cd /opt/nextcloud
docker compose up -d
```

### 5.4 Logları İzle

```bash
# Tüm loglar
docker compose logs -f

# Sadece Nextcloud
docker compose logs -f nextcloud
```

## 6️⃣ SSL/TLS Yapılandırması

### 6.1 Let's Encrypt (Certbot)

```bash
# Certbot kur
sudo apt install -y certbot

# Sertifika al (standalone)
sudo certbot certonly --standalone -d cloud.yourdomain.com

# Veya webroot ile (nginx çalışırken)
sudo certbot certonly --webroot -w /opt/nextcloud/configs/nginx/webroot -d cloud.yourdomain.com
```

### 6.2 Nginx SSL Yapılandırması

Sertifikaları Nginx'e bağla:

```bash
# Sertifika dizini oluştur
mkdir -p /opt/nextcloud/ssl

# Sertifikaları kopyala
sudo cp /etc/letsencrypt/live/cloud.yourdomain.com/fullchain.pem /opt/nextcloud/ssl/
sudo cp /etc/letsencrypt/live/cloud.yourdomain.com/privkey.pem /opt/nextcloud/ssl/
sudo chmod 644 /opt/nextcloud/ssl/*.pem
```

### 6.3 Otomatik Yenileme

```bash
# Crontab
sudo crontab -e
```

Ekleyin:
```cron
0 3 1 * * certbot renew --quiet && cp /etc/letsencrypt/live/cloud.yourdomain.com/*.pem /opt/nextcloud/ssl/ && docker compose -f /opt/nextcloud/docker-compose.yml restart nginx
```

## 7️⃣ İlk Erişim ve Yapılandırma

### 7.1 Web Arayüzü

1. Tarayıcıda açın: `https://cloud.yourdomain.com`
2. Admin bilgileriyle giriş yapın

### 7.2 Temel Ayarlar

Admin olarak giriş yaptıktan sonra:

1. **Settings → Administration → Basic settings**
   - Background jobs: Cron
   - Email server ayarları

2. **Settings → Administration → Security**
   - Enforce 2FA: Önerilen

3. **Settings → Administration → Sharing**
   - Default ayarları gözden geçirin

### 7.3 Önerilen Uygulamalar

Apps menüsünden yükleyin:
- **Files automated tagging** - Otomatik etiketleme
- **Full text search** - Tam metin arama
- **Preview Generator** - Önizleme oluşturucu
- **External storage support** - Harici depolama

## 8️⃣ Cron Job Yapılandırması

### 8.1 Host Cron

```bash
sudo crontab -e
```

Ekleyin:
```cron
# Nextcloud cron (her 5 dakika)
*/5 * * * * docker exec -u www-data nextcloud php cron.php

# Preview generation (gece 02:00)
0 2 * * * docker exec -u www-data nextcloud php occ preview:pre-generate

# Files scan (Pazar 03:00)
0 3 * * 0 docker exec -u www-data nextcloud php occ files:scan --all
```

### 8.2 Cron Modunu Aktifleştir

```bash
docker exec -u www-data nextcloud php occ background:cron
```

## 9️⃣ Doğrulama ve Test

### 9.1 Sistem Durumu

```bash
# Container durumu
docker compose ps

# Nextcloud durumu
docker exec -u www-data nextcloud php occ status

# Güvenlik taraması
docker exec -u www-data nextcloud php occ security:scan
```

### 9.2 NFS Bağlantı Testi

```bash
# Dosya yükleme testi
# 1. Web arayüzünden dosya yükleyin
# 2. NFS mount'ta kontrol edin:
ls -la /mnt/nextcloud-data/admin/files/
```

### 9.3 Performans Testi

```bash
# Basit yazma testi
dd if=/dev/zero of=/mnt/nextcloud-data/testfile bs=1M count=1000 oflag=direct
rm /mnt/nextcloud-data/testfile
```

## ✅ Checklist

- [ ] Ubuntu Server kuruldu
- [ ] Docker ve Docker Compose kuruldu
- [ ] NFS mount'lar yapılandırıldı
- [ ] Docker Compose ile servisler başlatıldı
- [ ] SSL sertifikası alındı
- [ ] Nextcloud web arayüzüne erişildi
- [ ] Cron job'lar yapılandırıldı
- [ ] Dosya yükleme testi başarılı

## ➡️ Sonraki Adımlar

1. [Güvenlik Sıkılaştırma](03-security-hardening.md)
2. [Performans Tuning](04-performance-tuning.md)
