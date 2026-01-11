# Güvenlik Sıkılaştırma Rehberi

Bu döküman, Nextcloud + TrueNAS sisteminin güvenlik yapılandırmasını anlatmaktadır.

## 1️⃣ SSL/TLS Yapılandırması

### 1.1 Let's Encrypt Sertifikası

```bash
# Certbot kurulumu
sudo apt install -y certbot

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

# Test renewal
sudo certbot renew --dry-run
```

### 1.3 SSL Test

```bash
# SSL Labs test (A+ rating hedefli)
# https://www.ssllabs.com/ssltest/

# Lokal test
openssl s_client -connect cloud.yourdomain.com:443 -tls1_3
```

## 2️⃣ Firewall (UFW)

### 2.1 Temel Kurallar

```bash
# Mevcut kuralları görüntüle
sudo ufw status verbose

# Sadece gerekli portları aç
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH (IP kısıtlamalı önerilir)
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'SSH from LAN'

# HTTP/HTTPS
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# Aktifleştir
sudo ufw enable
```

### 2.2 Rate Limiting

```bash
# SSH brute force koruması
sudo ufw limit ssh/tcp comment 'SSH rate limit'
```

### 2.3 Logging

```bash
# Logging aktifleştir
sudo ufw logging on
sudo ufw logging medium

# Log dosyası
tail -f /var/log/ufw.log
```

## 3️⃣ Fail2ban

### 3.1 Nextcloud Jail

```bash
# /etc/fail2ban/filter.d/nextcloud.conf
sudo tee /etc/fail2ban/filter.d/nextcloud.conf << 'EOF'
[Definition]
_groupsre = (?:(?:,?\s*"\w+":(?:"[^"]+"|\w+))*)
failregex = ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Login failed:
            ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Trusted domain error.
datepattern = ,?\s*"time"\s*:\s*"%%Y-%%m-%%d[T ]%%H:%%M:%%S(%%z)?"
EOF

# /etc/fail2ban/jail.d/nextcloud.conf
sudo tee /etc/fail2ban/jail.d/nextcloud.conf << 'EOF'
[nextcloud]
backend = auto
enabled = true
port = 80,443
protocol = tcp
filter = nextcloud
maxretry = 5
bantime = 86400
findtime = 600
logpath = /mnt/nextcloud-data/nextcloud.log
action = %(action_mwl)s
EOF
```

### 3.2 SSH Jail

```bash
sudo tee /etc/fail2ban/jail.d/sshd.conf << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
findtime = 600
EOF
```

### 3.3 Fail2ban Yönetimi

```bash
# Restart
sudo systemctl restart fail2ban

# Durum kontrol
sudo fail2ban-client status
sudo fail2ban-client status nextcloud

# Banlı IP'leri görüntüle
sudo fail2ban-client status nextcloud | grep "Banned IP"

# IP ban kaldırma
sudo fail2ban-client set nextcloud unbanip 1.2.3.4
```

## 4️⃣ Nextcloud Güvenlik Ayarları

### 4.1 config.php Güvenlik Ayarları

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

### 4.2 İki Faktörlü Kimlik Doğrulama (2FA)

```bash
# TOTP uygulaması kur
docker exec -u www-data nextcloud php occ app:enable twofactor_totp

# Admin için 2FA zorunlu
docker exec -u www-data nextcloud php occ twofactorauth:enforce --on
```

### 4.3 Güvenlik Taraması

```bash
# Nextcloud güvenlik taraması
docker exec -u www-data nextcloud php occ security:certificates

# Online tarama
# https://scan.nextcloud.com
```

## 5️⃣ TrueNAS Güvenliği

### 5.1 NFS Güvenliği

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

### 5.2 Web UI Güvenliği

1. **System → General Settings**
   - HTTPS için self-signed veya CA certificate
   - Session timeout ayarı

2. **Accounts → Users**
   - Güçlü admin şifresi
   - Gereksiz kullanıcıları devre dışı bırak

### 5.3 SSH Güvenliği

```bash
# SSH key-only authentication
# /etc/ssh/sshd_config
PasswordAuthentication no
PermitRootLogin prohibit-password
```

## 6️⃣ Ağ Segmentasyonu

### 6.1 VLAN Önerisi

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

### 6.2 Minimum Gerekli Portlar

| Kaynak | Hedef | Port | Protokol | Açıklama |
|--------|-------|------|----------|----------|
| Internet | Nextcloud | 443 | TCP | HTTPS |
| Nextcloud | TrueNAS | 2049 | TCP | NFS |
| Nextcloud | TrueNAS | 111 | TCP/UDP | Portmapper |
| Admin | TrueNAS | 443 | TCP | Web UI |
| Admin | Nextcloud | 22 | TCP | SSH |

## 7️⃣ Audit ve Logging

### 7.1 Nextcloud Audit Log

```bash
# Audit app aktifleştir
docker exec -u www-data nextcloud php occ app:enable admin_audit

# Log dosyası
/mnt/nextcloud-data/audit.log
```

### 7.2 Centralized Logging

```bash
# rsyslog ile merkezi log
sudo tee /etc/rsyslog.d/50-nextcloud.conf << 'EOF'
# Nextcloud logs
if $programname == 'nextcloud' then /var/log/nextcloud/nextcloud.log
& stop
EOF

sudo systemctl restart rsyslog
```

### 7.3 Log Rotation

```bash
sudo tee /etc/logrotate.d/nextcloud << 'EOF'
/mnt/nextcloud-data/nextcloud.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
    sharedscripts
    postrotate
        docker exec nextcloud kill -USR1 1
    endscript
}
EOF
```

## 8️⃣ Yedekleme Güvenliği

### 8.1 Şifreli Yedek

```bash
# GPG ile şifreli yedek
gpg --symmetric --cipher-algo AES256 backup.tar.gz

# Şifre çözme
gpg --decrypt backup.tar.gz.gpg > backup.tar.gz
```

### 8.2 Off-site Yedekleme

```bash
# rclone ile bulut yedekleme
rclone copy /opt/nextcloud/backups remote:nextcloud-backups --crypt-remote
```

## ✅ Güvenlik Checklist

### Sistem
- [ ] SSH key-only authentication
- [ ] Firewall (UFW) aktif
- [ ] Fail2ban yapılandırılmış
- [ ] Otomatik güvenlik güncellemeleri aktif
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
