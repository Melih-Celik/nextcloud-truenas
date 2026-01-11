# Nginx Proxy Manager (NPM) SSL Kurulum Rehberi

Bu rehber, Nextcloud için Nginx Proxy Manager üzerinden SSL sertifikası yapılandırmasını açıklar.

## Ön Gereksinimler

1. Nextcloud kurulumu tamamlanmış olmalı
2. NPM çalışır durumda olmalı
3. Domain adresiniz sunucunuzun IP'sine yönlendirilmiş olmalı (DNS A kaydı)
4. 80 ve 443 portları dışarıya açık olmalı

## Adım 1: NPM'e Giriş

1. NPM admin paneline erişin:
   - URL: `http://SUNUCU_IP:81`
   - İlk giriş bilgileri:
     - E-posta: `admin@example.com`
     - Şifre: `changeme`

2. İlk girişte şifrenizi değiştirmeniz istenecek

## Adım 2: Proxy Host Ekleme

1. **Hosts** > **Proxy Hosts** menüsüne gidin
2. **Add Proxy Host** butonuna tıklayın

### Details Sekmesi

| Alan | NPM Aynı Makinede | NPM Ayrı Makinede |
|------|-------------------|-------------------|
| Domain Names | `cloud.example.com` | `cloud.example.com` |
| Scheme | `http` | `http` |
| Forward Hostname / IP | `nginx` (Docker network) | Nextcloud sunucu IP (örn: `192.168.1.10`) |
| Forward Port | `8080` | `80` |
| Cache Assets | ✅ | ✅ |
| Block Common Exploits | ✅ | ✅ |
| Websockets Support | ✅ | ✅ |

> **📍 Port Farkı:**
> - **NPM aynı makinede:** Nextcloud nginx `8080`'de çalışır (NPM 80/443 kullandığı için)
> - **NPM ayrı makinede:** Nextcloud nginx `80`'de çalışır

### SSL Sekmesi

1. **SSL Certificate** dropdown'dan **Request a new SSL Certificate** seçin
2. Aşağıdaki seçenekleri işaretleyin:
   - ✅ Force SSL
   - ✅ HTTP/2 Support
   - ✅ HSTS Enabled
   - ✅ HSTS Subdomains (opsiyonel)
3. **Email Address for Let's Encrypt**: `admin@example.com` (geçerli e-posta)
4. ✅ I Agree to the Let's Encrypt Terms of Service
5. **Save** butonuna tıklayın

## Adım 3: Advanced Ayarları

**Custom Nginx Configuration** alanına aşağıdaki ayarları ekleyin:

```nginx
# Gerçek IP adresi iletimi (brute-force koruması için kritik!)
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

> ⚠️ **Kritik:** `X-Real-IP` ve `X-Forwarded-For` header'ları olmadan, Nextcloud tüm istekleri proxy IP'sinden geliyor olarak görür. Bu da brute-force korumasının yanlış çalışmasına ve "multiple invalid login attempts" hatasına neden olur.

## Adım 4: Nextcloud Yapılandırması

SSL etkinleştirildikten sonra Nextcloud'un bunu bilmesi gerekir:

```bash
# Sunucuya SSH ile bağlanın

# HTTPS zorlaması
docker exec -u www-data nextcloud php occ config:system:set overwrite.cli.url --value="https://cloud.example.com"
docker exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="https"

# === Trusted Proxies Ayarları ===

# NPM AYNI MAKİNEDE ise (Docker network):
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 0 --value="172.20.0.0/16"

# NPM AYRI MAKİNEDE ise (NPM sunucusunun IP'sini ekle):
# docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 0 --value="NPM_SUNUCU_IP"

# Genel private network aralıkları (her iki durumda da eklenebilir):
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 1 --value="10.0.0.0/8"
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 2 --value="192.168.0.0/16"
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 3 --value="172.16.0.0/12"

# Forwarded for headers ayarla (gerçek IP algılama için ÖNEMLİ)
docker exec -u www-data nextcloud php occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR"
docker exec -u www-data nextcloud php occ config:system:set forwarded_for_headers 1 --value="HTTP_X_REAL_IP"
```

> ⚠️ **Önemli:** `forwarded_for_headers` ayarı yapılmazsa Nextcloud gerçek IP adreslerini algılayamaz ve brute-force koruması yanlış çalışır.

## Adım 5: Collabora için Proxy Host ve WOPI Yapılandırması

Collabora Online kullanıyorsanız, WOPI protokolünün düzgün çalışması için doğru yapılandırma kritiktir.

### WOPI Nedir?

WOPI (Web Application Open Platform Interface), Nextcloud ve Collabora arasındaki dosya alışverişini sağlayan protokoldür:
- Nextcloud → Collabora: "Bu dosyayı düzenle" (WOPI CheckFileInfo, GetFile)
- Collabora → Nextcloud: "Değişiklikleri kaydet" (WOPI PutFile)

### 5.1 Collabora Environment Ayarları

`.env` dosyasında şu değişkenlerin doğru ayarlandığından emin olun:

```bash
# Collabora'nın public URL'i (NPM üzerinden erişilen)
COLLABORA_SERVER_NAME=office.example.com

# Nextcloud'un public URL'i (WOPI istekleri için)
# Port numarası DAHİL EDİLMELİ!
COLLABORA_WOPI_URL=https://cloud.example.com:443
```

### 5.2 NPM Proxy Host Ekleme

1. **Hosts → Proxy Hosts → Add Proxy Host**
2. **Details sekmesi:**
   - Domain Names: `office.example.com`
   - Scheme: `http`
   - Forward Hostname / IP:
     - **NPM aynı makinede:** `collabora` (Docker network)
     - **NPM ayrı makinede:** Nextcloud sunucu IP (örn: `192.168.1.10`)
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
   
   # WebSocket desteği (Collabora için zorunlu)
   proxy_http_version 1.1;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   
   # Timeout ayarları (uzun düzenlemeler için)
   proxy_connect_timeout 3600;
   proxy_send_timeout 3600;
   proxy_read_timeout 3600;
   ```

> **📍 NPM Ayrı Makinede İse:**
> - Nextcloud sunucusunda `9980` portunu firewall'da açın
> - Veya Collabora sadece localhost'tan erişilebilir olsun, NPM'i de aynı makinede çalıştırın

### 5.3 Nextcloud'da Collabora Ayarları

1. **Nextcloud Office uygulamasını kur:**
   - Ayarlar → Uygulamalar → Office & text → "Nextcloud Office"

2. **Collabora sunucusunu yapılandır:**
   - Ayarlar → Yönetim → Nextcloud Office
   - "Use your own server" seç
   - URL: `https://office.example.com`

3. **WOPI Doğrulama:**
   ```bash
   # Collabora'dan WOPI discovery al
   curl -s https://office.example.com/hosting/discovery | head -20
   
   # Collabora capabilities kontrol
   curl -s https://office.example.com/hosting/capabilities | jq .
   ```

### 5.4 WOPI Sorun Giderme

#### "Could not establish connection to the Collabora Online server"

```bash
# 1. Collabora container çalışıyor mu?
docker ps | grep collabora

# 2. NPM'den Collabora'ya erişim var mı?
docker exec nginx-proxy-manager curl -I http://collabora:9980/hosting/discovery

# 3. WOPI URL doğru mu?
docker logs collabora 2>&1 | grep -i "aliasgroup\|wopi"
```

#### "WOPI host did not respond"

```bash
# Collabora'dan Nextcloud'a erişim test et
docker exec collabora curl -kI https://cloud.example.com

# DNS çözümlemesi
docker exec collabora nslookup cloud.example.com
```

#### Doküman açılıyor ama kaydedilmiyor

WebSocket bağlantısı kopuyor olabilir:
1. NPM'de "Websockets Support" aktif mi?
2. Advanced ayarlarda `proxy_http_version 1.1` ve `Upgrade` header'ları var mı?

## Adım 6: Doğrulama

1. `https://cloud.example.com` adresine gidin
2. Tarayıcıda kilit simgesine tıklayın
3. Sertifika bilgilerini kontrol edin (Let's Encrypt olmalı)

### IP Algılama Testi

Gerçek IP'nizin doğru algılandığını test edin:

```bash
# Nextcloud loglarından giriş denemelerini kontrol edin
docker exec nextcloud tail -f /var/www/html/data/nextcloud.log | grep -i "login"
```

Log'da kendi gerçek IP adresinizi görmelisiniz, proxy IP'sini (172.x.x.x) değil.

## Sorun Giderme

### SSL Sertifikası Alınamıyor

1. **DNS kontrolü**: Domain'in sunucu IP'sine yönlendiğinden emin olun
   ```bash
   nslookup cloud.example.com
   ```

2. **Port kontrolü**: 80 ve 443 portlarının açık olduğundan emin olun
   ```bash
   sudo firewall-cmd --list-ports
   # Veya
   sudo ufw status
   ```

3. **Let's Encrypt rate limit**: Çok fazla deneme yaptıysanız bir süre bekleyin

### "Bad Gateway" Hatası

1. Nextcloud container'ının çalıştığından emin olun:
   ```bash
   docker ps | grep nextcloud
   ```

2. NPM'in Nextcloud'a erişebildiğinden emin olun:
   ```bash
   docker exec nginx-proxy-manager curl -I http://nextcloud
   ```

### Mixed Content Uyarısı

Nextcloud config'de HTTPS zorlamasını etkinleştirin:
```bash
docker exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="https"
```

### "Multiple Invalid Login Attempts" Hatası

Bu hata, Nextcloud'un gerçek IP adresini algılayamamasından kaynaklanır. Tüm istekler proxy IP'sinden geliyor gibi görünür.

**Çözüm:**

1. NPM'de Advanced ayarlarında şu header'ların olduğundan emin olun:
   ```nginx
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   ```

2. Nextcloud'da forwarded_for_headers ayarlayın:
   ```bash
   docker exec -u www-data nextcloud php occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR"
   docker exec -u www-data nextcloud php occ config:system:set forwarded_for_headers 1 --value="HTTP_X_REAL_IP"
   ```

3. Trusted proxies'i genişletin:
   ```bash
   docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 0 --value="172.20.0.0/16"
   docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 1 --value="10.0.0.0/8"
   docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 2 --value="192.168.0.0/16"
   docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 3 --value="172.16.0.0/12"
   ```

4. Mevcut engelleri temizleyin:
   ```bash
   # Belirli IP için
   docker exec -u www-data nextcloud php occ security:bruteforce:reset SENIN_IP_ADRESIN
   
   # Tüm engeller için
   docker exec -u www-data nextcloud php occ security:bruteforce:reset all
   ```

5. Container'ları yeniden başlatın:
   ```bash
   docker compose restart nginx nextcloud
   ```

## Yedek SSL Sertifikası (Opsiyonel)

Mevcut bir sertifikanız varsa:

1. **SSL Certificates** > **Add SSL Certificate** > **Custom**
2. Sertifika ve anahtar dosyalarını yükleyin
3. Proxy Host'ta bu sertifikayı seçin

## Wildcard Sertifika (Opsiyonel)

DNS Challenge ile wildcard sertifika almak için:

1. **SSL Certificates** > **Add SSL Certificate** > **Let's Encrypt**
2. **Use a DNS Challenge** seçin
3. DNS sağlayıcınızı seçin (Cloudflare, DigitalOcean, vb.)
4. API credentials'ı girin
5. Domain: `*.example.com`

## Güvenlik İpuçları

1. **HSTS**: Her zaman etkinleştirin (tarayıcıları HTTPS kullanmaya zorlar)
2. **HTTP/2**: Performans için etkinleştirin
3. **Force SSL**: HTTP isteklerini HTTPS'e yönlendirir
4. **TLS 1.3**: NPM varsayılan olarak destekler

## Sertifika Yenileme

Let's Encrypt sertifikaları 90 günlüktür. NPM otomatik olarak yeniler, ancak kontrol etmek için:

1. **SSL Certificates** menüsüne gidin
2. Sertifikanızın son kullanma tarihini kontrol edin
3. Gerekirse **Renew Now** butonuna tıklayın

---

**Notlar:**
- İlk SSL kurulumunda birkaç dakika bekleyin
- DNS propagasyonu 24 saate kadar sürebilir (genelde dakikalar içinde)
- Rate limit hatası alırsanız staging ortamını deneyin
