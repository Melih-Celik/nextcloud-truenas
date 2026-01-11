# Güvenlik Sıkılaştırma Rehberi (AlmaLinux 10)

Bu döküman, Nextcloud + TrueNAS sisteminin güvenlik yapılandırmasını anlatmaktadır.

## 1️⃣ SSL/TLS Yapılandırması

### 1.1 Let's Encrypt Sertifikası

```bash
# Certbot kurulumu
sudo dnf install -y certbot

# Nginx'i geçici olarak durdur
cd /opt/nextcloud
docker compose stop nginx

# Sertifika al
sudo certbot certonly --standalone \
    -d cloud.yourdomain.com \
    --email admin@yourdomain.com \
    --agree-tos \
    --non-interactive

# Sertifikaları kopyala
sudo cp /etc/letsencrypt/live/cloud.yourdomain.com/fullchain.pem /opt/nextcloud/ssl/
sudo cp /etc/letsencrypt/live/cloud.yourdomain.com/privkey.pem /opt/nextcloud/ssl/
sudo chmod 644 /opt/nextcloud/ssl/*.pem

# Nginx'i başlat
docker compose start nginx
```

### 1.2 Otomatik Yenileme

```bash
# Renewal hook scripti oluştur
sudo tee /etc/letsencrypt/renewal-hooks/deploy/nextcloud.sh << 'EOF'
#!/bin/bash
cp /etc/letsencrypt/live/cloud.yourdomain.com/fullchain.pem /opt/nextcloud/ssl/
cp /etc/letsencrypt/live/cloud.yourdomain.com/privkey.pem /opt/nextcloud/ssl/
docker compose -f /opt/nextcloud/docker-compose.yml restart nginx
EOF

sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/nextcloud.sh

# Certbot timer'ı kontrol et (AlmaLinux'ta systemd timer kullanır)
sudo systemctl status certbot-renew.timer
sudo systemctl enable --now certbot-renew.timer

# Manuel test
sudo certbot renew --dry-run
```

### 1.3 SSL Test

```bash
# SSL Labs test (A+ rating hedefli)
# https://www.ssllabs.com/ssltest/

# Lokal test
openssl s_client -connect cloud.yourdomain.com:443 -tls1_3
```

## 2️⃣ Firewall (firewalld)

### 2.1 Temel Yapılandırma

```bash
# Firewalld'ı başlat ve etkinleştir
sudo systemctl enable --now firewalld

# Mevcut durumu görüntüle
sudo firewall-cmd --state
sudo firewall-cmd --list-all
```

### 2.2 Zone Yapılandırması

```bash
# Public zone için kurallar (varsayılan)
# Sadece gerekli servisleri aç
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https
sudo firewall-cmd --permanent --zone=public --add-service=ssh

# Gereksiz servisleri kaldır
sudo firewall-cmd --permanent --zone=public --remove-service=cockpit 2>/dev/null || true
sudo firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client 2>/dev/null || true

# Kuralları uygula
sudo firewall-cmd --reload

# Doğrula
sudo firewall-cmd --list-all
```

### 2.3 SSH için IP Kısıtlaması (Önerilen)

```bash
# Sadece belirli IP'lerden SSH izni (rich rule)
sudo firewall-cmd --permanent --zone=public --remove-service=ssh
sudo firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" service name="ssh" accept'

# Veya trusted zone kullan
sudo firewall-cmd --permanent --zone=trusted --add-source=192.168.1.0/24
sudo firewall-cmd --permanent --zone=trusted --add-service=ssh

sudo firewall-cmd --reload
```

### 2.4 Rate Limiting (DDoS Koruması)

```bash
# HTTP/HTTPS için rate limiting
sudo firewall-cmd --permanent --add-rich-rule='rule service name="http" limit value="25/m" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule service name="https" limit value="25/m" accept'

sudo firewall-cmd --reload
```

### 2.5 Logging

```bash
# Dropped paketleri logla
sudo firewall-cmd --set-log-denied=all

# Log dosyası
sudo journalctl -f -t kernel | grep -i firewall
```

## 3️⃣ Fail2ban

### 3.1 Kurulum

```bash
# Fail2ban kur
sudo dnf install -y fail2ban fail2ban-firewalld

# Servisi başlat
sudo systemctl enable --now fail2ban
```

### 3.2 Nextcloud Jail

```bash
# Nextcloud filter oluştur
sudo tee /etc/fail2ban/filter.d/nextcloud.conf << 'EOF'
[Definition]
_groupsre = (?:(?:,?\s*"\w+":(?:"[^"]+"|\w+))*)
failregex = ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Login failed:
            ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Trusted domain error.
datepattern = ,?\s*"time"\s*:\s*"%%Y-%%m-%%d[T ]%%H:%%M:%%S(%%z)?"
EOF

# Nextcloud jail oluştur
sudo tee /etc/fail2ban/jail.d/nextcloud.local << 'EOF'
[nextcloud]
backend = auto
enabled = true
port = http,https
protocol = tcp
filter = nextcloud
maxretry = 5
bantime = 86400
findtime = 600
logpath = /mnt/nextcloud-data/nextcloud.log
banaction = firewallcmd-rich-rules[actiontype=<multiport>]
banaction_allports = firewallcmd-rich-rules[actiontype=<allports>]
EOF
```

### 3.3 SSH Jail

```bash
sudo tee /etc/fail2ban/jail.d/sshd.local << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 3
bantime = 86400
findtime = 600
banaction = firewallcmd-rich-rules[actiontype=<multiport>]
EOF
```

### 3.4 Fail2ban Yönetimi

```bash
# Servisi yeniden başlat
sudo systemctl restart fail2ban

# Durum kontrol
sudo fail2ban-client status
sudo fail2ban-client status nextcloud
sudo fail2ban-client status sshd

# Banlı IP'leri görüntüle
sudo fail2ban-client status nextcloud | grep "Banned IP"

# IP ban kaldırma
sudo fail2ban-client set nextcloud unbanip 1.2.3.4

# Logları izle
sudo tail -f /var/log/fail2ban.log
```

## 4️⃣ SELinux Yapılandırması

### 4.1 SELinux Durumu

```bash
# Durumu kontrol et
getenforce
sestatus

# Enforcing modda olmalı (önerilen)
sudo setenforce 1
```

### 4.2 Docker ve NFS için Boolean'lar

```bash
# Gerekli boolean'ları ayarla
sudo setsebool -P container_use_nfs 1
sudo setsebool -P httpd_use_nfs 1
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_can_network_connect_db 1
sudo setsebool -P container_manage_cgroup 1

# Doğrula
getsebool -a | grep -E "(container|httpd|nfs)"
```

### 4.3 SELinux Troubleshooting

```bash
# Audit loglarını kontrol et
sudo ausearch -m avc -ts recent

# Önerilen policy oluştur
sudo ausearch -m avc -ts recent | audit2allow -M nextcloud_custom
sudo semodule -i nextcloud_custom.pp

# Geçici olarak permissive (sorun giderme için)
# sudo setenforce 0

# Kalıcı olarak permissive yapmak için (önerilmez):
# sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

## 5️⃣ Nextcloud Güvenlik Ayarları

### 5.1 config.php Güvenlik Ayarları

```php
<?php
$CONFIG = array (
  // Brute force koruması
  'auth.bruteforce.protection.enabled' => true,
  
  // HTTPS zorunlu
  'overwriteprotocol' => 'https',
  'force_language' => 'tr',
  'default_phone_region' => 'TR',
  
  // Güçlü şifre politikası
  'password_policy' => array(
    'minLength' => 12,
    'enforceNumericCharacters' => true,
    'enforceSpecialCharacters' => true,
    'enforceUpperLowerCase' => true,
  ),
  
  // Session güvenliği
  'session_lifetime' => 3600,  // 1 saat
  'session_keepalive' => true,
  'auto_logout' => true,
  
  // Token authentication
  'token_auth_enforced' => false,  // 2FA ile kullanılabilir
  
  // Dosya kilitlenmesi
  'filelocking.enabled' => true,
);
```

### 5.2 İki Faktörlü Kimlik Doğrulama (2FA)

```bash
# TOTP uygulaması kur
docker exec -u www-data nextcloud php occ app:enable twofactor_totp

# Admin için 2FA zorunlu
docker exec -u www-data nextcloud php occ twofactorauth:enforce --on
```

### 5.3 Güvenlik Taraması

```bash
# Nextcloud güvenlik taraması
docker exec -u www-data nextcloud php occ security:certificates

# Online tarama
# https://scan.nextcloud.com
```

## 6️⃣ TrueNAS Güvenliği

### 6.1 NFS Güvenliği

```yaml
# TrueNAS NFS Share ayarları
Security:
  - sys (AUTH_SYS)
  
Maproot User: root
Maproot Group: wheel

# IP kısıtlaması
Authorized Networks: 192.168.1.10/32
Authorized Hosts: 192.168.1.10
```

### 6.2 Web UI Güvenliği

1. **System → General Settings**
   - HTTPS için self-signed veya CA certificate
   - Session timeout ayarı

2. **Accounts → Users**
   - Güçlü admin şifresi
   - Gereksiz kullanıcıları devre dışı bırak

### 6.3 SSH Güvenliği

```bash
# SSH key-only authentication
# /etc/ssh/sshd_config
PasswordAuthentication no
PermitRootLogin prohibit-password
```

## 7️⃣ Ağ Segmentasyonu

### 7.1 VLAN Önerisi

```
VLAN 10 - Management (TrueNAS Web UI, SSH)
├── 192.168.10.0/24

VLAN 20 - Storage (NFS traffic)
├── 192.168.20.0/24
├── TrueNAS: 192.168.20.20
└── Nextcloud: 192.168.20.10

VLAN 30 - DMZ (Public access)
├── 192.168.30.0/24
└── Nextcloud Public IP
```

### 7.2 Firewalld Zone'ları ile Segmentasyon

```bash
# Farklı interface'ler için farklı zone'lar
# Internal network (storage)
sudo firewall-cmd --permanent --zone=internal --add-interface=eth1
sudo firewall-cmd --permanent --zone=internal --add-service=nfs

# Public network
sudo firewall-cmd --permanent --zone=public --add-interface=eth0
sudo firewall-cmd --permanent --zone=public --add-service=https

sudo firewall-cmd --reload
```

### 7.3 Minimum Gerekli Portlar

| Kaynak | Hedef | Port | Protokol | Açıklama |
|--------|-------|------|----------|----------|
| Internet | Nextcloud | 443 | TCP | HTTPS |
| Nextcloud | TrueNAS | 2049 | TCP | NFS |
| Nextcloud | TrueNAS | 111 | TCP/UDP | Portmapper |
| Admin | TrueNAS | 443 | TCP | Web UI |
| Admin | Nextcloud | 22 | TCP | SSH |

## 8️⃣ Audit ve Logging

### 8.1 Nextcloud Audit Log

```bash
# Audit app aktifleştir
docker exec -u www-data nextcloud php occ app:enable admin_audit

# Log dosyası
/mnt/nextcloud-data/audit.log
```

### 8.2 Centralized Logging (rsyslog)

```bash
# rsyslog yapılandırması
sudo tee /etc/rsyslog.d/50-nextcloud.conf << 'EOF'
# Nextcloud logs
if $programname == 'nextcloud' then /var/log/nextcloud/nextcloud.log
& stop
EOF

sudo mkdir -p /var/log/nextcloud
sudo systemctl restart rsyslog
```

### 8.3 Log Rotation

```bash
sudo tee /etc/logrotate.d/nextcloud << 'EOF'
/mnt/nextcloud-data/nextcloud.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 33 33
    sharedscripts
    postrotate
        docker exec nextcloud kill -USR1 1 2>/dev/null || true
    endscript
}
EOF
```

## 9️⃣ Yedekleme Güvenliği

### 9.1 Şifreli Yedek

```bash
# GPG ile şifreli yedek
gpg --symmetric --cipher-algo AES256 backup.tar.gz

# Şifre çözme
gpg --decrypt backup.tar.gz.gpg > backup.tar.gz
```

### 9.2 Off-site Yedekleme

```bash
# rclone kurulumu
sudo dnf install -y rclone

# rclone ile bulut yedekleme
rclone copy /opt/nextcloud/backups remote:nextcloud-backups --crypt-remote
```

## ✅ Güvenlik Checklist

### Sistem
- [ ] SSH key-only authentication
- [ ] Firewalld aktif ve yapılandırılmış
- [ ] Fail2ban yapılandırılmış
- [ ] SELinux enforcing modda
- [ ] Otomatik güvenlik güncellemeleri aktif (`dnf-automatic`)
- [ ] Gereksiz servisler kapalı

### Nextcloud
- [ ] HTTPS zorunlu
- [ ] Let's Encrypt sertifikası (A+ rating)
- [ ] 2FA etkin
- [ ] Brute force koruması aktif
- [ ] Güvenlik taraması geçti
- [ ] Audit logging aktif

### TrueNAS
- [ ] NFS IP kısıtlaması
- [ ] Web UI HTTPS
- [ ] Güçlü admin şifresi
- [ ] SSH güvenli yapılandırılmış

### Ağ
- [ ] Gereksiz portlar kapalı
- [ ] VLAN segmentasyonu (önerilir)
- [ ] Intrusion detection (önerilir)

### Yedekleme
- [ ] Düzenli yedekleme aktif
- [ ] Yedekler şifreli
- [ ] Off-site yedekleme
- [ ] Yedek geri yükleme testi yapıldı
