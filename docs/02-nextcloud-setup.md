# Nextcloud Sunucusu Kurulum Rehberi (AlmaLinux 10)

Bu döküman, Docker üzerinde Nextcloud kurulumunu ve TrueNAS NFS entegrasyonunu anlatmaktadır.

## 📋 Ön Gereksinimler

- AlmaLinux 10 Server
- Minimum 8GB RAM, 4 CPU Core
- 64GB+ SSD (OS ve Docker için)
- TrueNAS NFS paylaşımları hazır
- Domain adı ve SSL sertifikası (production için)

## 1️⃣ AlmaLinux Server Kurulumu

### 1.1 Minimal Kurulum

1. AlmaLinux 10 ISO'yu indirin (https://almalinux.org/)
2. Minimal installation seçin
3. OpenSSH server'ı kurun
4. Statik IP yapılandırın

### 1.2 Temel Yapılandırma

```bash
# Sistemi güncelle
sudo dnf update -y

# EPEL ve CRB repository ekle
sudo dnf install -y epel-release
sudo dnf config-manager --set-enabled crb

# Gerekli paketleri kur
sudo dnf install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    iotop \
    nfs-utils \
    ca-certificates \
    gnupg2 \
    tar \
    bzip2 \
    unzip \
    policycoreutils-python-utils \
    bash-completion \
    net-tools \
    bind-utils

# Timezone ayarla
sudo timedatectl set-timezone Europe/Istanbul

# Hostname ayarla
sudo hostnamectl set-hostname nextcloud-server
```

### 1.3 Statik IP (NetworkManager)

```bash
# Mevcut bağlantıları listele
nmcli connection show

# Statik IP ayarla (connection adınıza göre değiştirin)
sudo nmcli connection modify "enp0s3" \
    ipv4.addresses 192.168.1.10/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "8.8.8.8,8.8.4.4" \
    ipv4.method manual

# Bağlantıyı yeniden başlat
sudo nmcli connection down "enp0s3"
sudo nmcli connection up "enp0s3"

# Doğrula
ip addr show
nmcli connection show "enp0s3"
```

### 1.4 SELinux Yapılandırması

```bash
# SELinux durumunu kontrol et
getenforce
sestatus

# NFS ve container için SELinux boolean'ları ayarla
sudo setsebool -P httpd_use_nfs 1
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P container_use_nfs 1
sudo setsebool -P container_manage_cgroup 1

# Boolean'ları doğrula
getsebool httpd_use_nfs httpd_can_network_connect container_use_nfs
```

> **Not:** SELinux'u kapatmak yerine doğru şekilde yapılandırmak güvenlik açısından önerilir. Sorun yaşarsanız audit loglarını kontrol edin: `sudo ausearch -m avc -ts recent`

## 2️⃣ Docker Kurulumu

### 2.1 Docker Engine

```bash
# Eski versiyonları kaldır (varsa)
sudo dnf remove -y docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    podman \
    runc

# Docker repository ekle
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Docker kur
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker'ı başlat ve etkinleştir
sudo systemctl enable --now docker

# Kullanıcıyı docker grubuna ekle
sudo usermod -aG docker $USER

# Grubu aktifleştir (veya logout/login yapın)
newgrp docker
```

### 2.2 Doğrulama

```bash
# Versiyon kontrolü
docker --version
docker compose version

# Servis durumu
sudo systemctl status docker

# Test container
docker run hello-world
```

## 3️⃣ NFS Mount Yapılandırması

### 3.1 NFS Paketleri ve Servisleri

```bash
# NFS utilities zaten kurulu olmalı, servisleri başlat
sudo systemctl enable --now nfs-client.target
sudo systemctl enable --now rpcbind

# Servis durumlarını kontrol et
systemctl status nfs-client.target
systemctl status rpcbind
```

### 3.2 Mount Noktaları Oluştur

```bash
# Mount dizinlerini oluştur
sudo mkdir -p /mnt/nextcloud-data
sudo mkdir -p /mnt/nextcloud-config
```

### 3.3 NFS Mount Test

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

### 3.4 Kalıcı Mount (fstab)

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
# Syntax kontrolü
sudo mount -a

# Doğrula
df -h | grep nextcloud
mount | grep nfs
```

### 3.5 NFS Mount Seçenekleri Açıklaması

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

## 4️⃣ Firewall Yapılandırması

### 4.1 Firewalld Kuralları

```bash
# Firewalld durumunu kontrol et ve başlat
sudo systemctl enable --now firewalld
sudo systemctl status firewalld

# HTTP ve HTTPS izni
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

# NFS client (giden bağlantılar için genelde gerekli değil, ama emin olmak için)
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=nfs3
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --permanent --add-service=mountd

# Kuralları yeniden yükle
sudo firewall-cmd --reload

# Durumu kontrol et
sudo firewall-cmd --list-all
```

## 5️⃣ Proje Dizini Hazırlığı

```bash
# Proje dizini
sudo mkdir -p /opt/nextcloud
cd /opt/nextcloud

# Gerekli dizinleri oluştur
sudo mkdir -p configs/nginx
sudo mkdir -p configs/php
sudo mkdir -p configs/redis
sudo mkdir -p db-data
sudo mkdir -p redis-data
sudo mkdir -p ssl

# İzinleri ayarla
sudo chown -R $USER:$USER /opt/nextcloud
```

## 6️⃣ Docker Compose ile Deployment

### 6.1 Dosyaları Kopyala

Repository'den dosyaları `/opt/nextcloud` dizinine kopyalayın:

```bash
# Git clone veya manuel kopyalama
cp docker/docker-compose.yml /opt/nextcloud/
cp docker/.env.example /opt/nextcloud/.env
cp -r docker/configs/* /opt/nextcloud/configs/
```

### 6.2 Environment Dosyasını Düzenle

```bash
vim /opt/nextcloud/.env
```

Zorunlu değişiklikleri yapın:
- `NEXTCLOUD_ADMIN_PASSWORD`
- `POSTGRES_PASSWORD`
- `REDIS_PASSWORD`
- `NEXTCLOUD_TRUSTED_DOMAINS`

### 6.3 Başlat

```bash
cd /opt/nextcloud
docker compose up -d
```

### 6.4 Logları İzle

```bash
# Tüm loglar
docker compose logs -f

# Sadece Nextcloud
docker compose logs -f nextcloud
```

## 7️⃣ SSL/TLS Yapılandırması

### 7.1 Let's Encrypt (Certbot)

```bash
# Certbot kur
sudo dnf install -y certbot

# Nginx container'ı geçici olarak durdur
cd /opt/nextcloud
docker compose stop nginx

# Sertifika al (standalone)
sudo certbot certonly --standalone -d cloud.yourdomain.com

# Nginx'i yeniden başlat
docker compose start nginx
```

### 7.2 Sertifikaları Kopyala

```bash
# Sertifika dizini oluştur
mkdir -p /opt/nextcloud/ssl

# Sertifikaları kopyala
sudo cp /etc/letsencrypt/live/cloud.yourdomain.com/fullchain.pem /opt/nextcloud/ssl/
sudo cp /etc/letsencrypt/live/cloud.yourdomain.com/privkey.pem /opt/nextcloud/ssl/
sudo chmod 644 /opt/nextcloud/ssl/*.pem
sudo chown $USER:$USER /opt/nextcloud/ssl/*.pem

# Nginx'i yeniden başlat
docker compose restart nginx
```

### 7.3 Otomatik Yenileme

```bash
# Crontab
sudo crontab -e
```

Ekleyin:
```cron
0 3 1 * * certbot renew --quiet --pre-hook "docker compose -f /opt/nextcloud/docker-compose.yml stop nginx" --post-hook "cp /etc/letsencrypt/live/cloud.yourdomain.com/*.pem /opt/nextcloud/ssl/ && docker compose -f /opt/nextcloud/docker-compose.yml start nginx"
```

## 8️⃣ İlk Erişim ve Yapılandırma

### 8.1 Web Arayüzü

1. Tarayıcıda açın: `https://cloud.yourdomain.com`
2. Admin bilgileriyle giriş yapın (.env dosyasındaki)

### 8.2 Temel Ayarlar

Admin olarak giriş yaptıktan sonra:

1. **Settings → Administration → Basic settings**
   - Background jobs: Cron
   - Email server ayarları

2. **Settings → Administration → Security**
   - Enforce 2FA: Önerilen

3. **Settings → Administration → Sharing**
   - Default ayarları gözden geçirin

### 8.3 Önerilen Uygulamalar

Apps menüsünden yükleyin:
- **Files automated tagging** - Otomatik etiketleme
- **Full text search** - Tam metin arama
- **Preview Generator** - Önizleme oluşturucu
- **External storage support** - Harici depolama

## 9️⃣ Cron Job Yapılandırması

### 9.1 Host Cron

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

### 9.2 Cron Modunu Aktifleştir

```bash
docker exec -u www-data nextcloud php occ background:cron
```

## 🔟 Doğrulama ve Test

### 10.1 Sistem Durumu

```bash
# Container durumu
docker compose ps

# Nextcloud durumu
docker exec -u www-data nextcloud php occ status

# Güvenlik taraması
docker exec -u www-data nextcloud php occ security:certificates
```

### 10.2 NFS Bağlantı Testi

```bash
# Dosya yükleme testi
# 1. Web arayüzünden dosya yükleyin
# 2. NFS mount'ta kontrol edin:
ls -la /mnt/nextcloud-data/admin/files/
```

### 10.3 Performans Testi

```bash
# Basit yazma testi
dd if=/dev/zero of=/mnt/nextcloud-data/testfile bs=1M count=1000 oflag=direct
rm /mnt/nextcloud-data/testfile
```

## ✅ Checklist

- [ ] AlmaLinux 10 Server kuruldu
- [ ] Docker ve Docker Compose kuruldu
- [ ] SELinux boolean'ları ayarlandı
- [ ] NFS mount'lar yapılandırıldı
- [ ] Firewalld kuralları eklendi
- [ ] Docker Compose ile servisler başlatıldı
- [ ] SSL sertifikası alındı
- [ ] Nextcloud web arayüzüne erişildi
- [ ] Cron job'lar yapılandırıldı
- [ ] Dosya yükleme testi başarılı

## ➡️ Sonraki Adımlar

1. [Güvenlik Sıkılaştırma](03-security-hardening.md)
2. [Performans Tuning](04-performance-tuning.md)
