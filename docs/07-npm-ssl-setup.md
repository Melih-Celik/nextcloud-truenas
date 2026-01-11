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

| Alan | Değer |
|------|-------|
| Domain Names | `cloud.example.com` (kendi domain'iniz) |
| Scheme | `http` |
| Forward Hostname / IP | `nextcloud` (Docker network) veya `SUNUCU_IP` |
| Forward Port | `80` |
| Cache Assets | ✅ |
| Block Common Exploits | ✅ |
| Websockets Support | ✅ |

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
# Nextcloud için gerekli header'lar
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;

# Büyük dosya yüklemeleri için
client_max_body_size 16G;
proxy_request_buffering off;

# Timeout ayarları
proxy_connect_timeout 3600;
proxy_send_timeout 3600;
proxy_read_timeout 3600;

# WebDAV için
proxy_buffering off;
```

## Adım 4: Nextcloud Yapılandırması

SSL etkinleştirildikten sonra Nextcloud'un bunu bilmesi gerekir:

```bash
# Sunucuya SSH ile bağlanın
docker exec -u www-data nextcloud php occ config:system:set overwrite.cli.url --value="https://cloud.example.com"
docker exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="https"

# Trusted proxy ekle (NPM aynı sunucudaysa)
docker exec -u www-data nextcloud php occ config:system:set trusted_proxies 0 --value="172.20.0.0/16"
```

## Adım 5: Doğrulama

1. `https://cloud.example.com` adresine gidin
2. Tarayıcıda kilit simgesine tıklayın
3. Sertifika bilgilerini kontrol edin (Let's Encrypt olmalı)

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
