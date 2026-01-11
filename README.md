# 🗄️ Nextcloud + TrueNAS Kurumsal Dosya Paylaşım Sistemi

60TB kapasiteli, self-hosted bulut depolama çözümü.

## � Hızlı Başlangıç (İnteraktif Kurulum)

En kolay kurulum yöntemi interaktif kurulum sihirbazını kullanmaktır:

```bash
# Repoyu klonlayın
git clone https://github.com/your-repo/nextcloud-truenas.git
cd nextcloud-truenas

# İnteraktif kurulum sihirbazını başlatın
./setup.sh
```

Kurulum sihirbazı size şu konularda sorular soracak:
- 📡 Ağ yapılandırması (TrueNAS IP, Nextcloud sunucu IP)
- 🌐 Domain ve SSL ayarları
- 🔀 Reverse proxy seçimi (Nginx Proxy Manager, harici proxy, veya doğrudan erişim)
- 💾 NFS depolama ayarları
- ☁️ Nextcloud admin bilgileri
- 🗄️ Veritabanı şifreleri (otomatik oluşturulabilir)
- 📧 E-posta bildirimleri (opsiyonel)
- 🔐 Güvenlik ayarları (Fail2ban, Firewall)
- 💾 Yedekleme yapılandırması

## �📐 Sistem Mimarisi

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              İNTERNET                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         FIREWALL / ROUTER                                │
│                    (Port 443 → Nextcloud Server)                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │         İÇ AĞ (LAN)           │
                    │        192.168.1.0/24         │
                    └───────────────┬───────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
            ▼                       ▼                       ▼
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
│  NEXTCLOUD SERVER │   │  TRUENAS SERVER   │   │   CLIENT'LAR      │
│  192.168.1.10     │   │  192.168.1.20     │   │                   │
├───────────────────┤   ├───────────────────┤   │  • Windows PC     │
│  • AlmaLinux 10   │   │  • TrueNAS SCALE  │   │  • macOS          │
│  • Docker         │   │  • ZFS Storage    │   │  • iPhone/Android │
│  • Nginx          │   │  • NFS Server     │   │  • Linux          │
│  • Nextcloud      │◄──┤  • 60TB Pool      │   │                   │
│  • PostgreSQL     │NFS│  • RAIDZ2         │   └───────────────────┘
│  • Redis          │   │                   │
└───────────────────┘   └───────────────────┘
```

## 🖥️ Donanım Gereksinimleri

### TrueNAS Sunucusu (Storage)
| Bileşen | Minimum | Önerilen |
|---------|---------|----------|
| CPU | Intel i5 / Xeon E3 | Intel Xeon E-2300 / AMD EPYC |
| RAM | 32 GB ECC | 64 GB ECC |
| Boot | 2x 32GB SSD (Mirror) | 2x 64GB NVMe (Mirror) |
| Data | 8x 10TB NAS HDD | 8x 10TB Enterprise HDD |
| SLOG | - | 32GB Intel Optane |
| L2ARC | - | 512GB Enterprise NVMe |
| NIC | 1 Gbps | 10 Gbps |

### Nextcloud Sunucusu (Application)
| Bileşen | Minimum | Önerilen |
|---------|---------|----------|
| CPU | 4 Core | 8 Core |
| RAM | 8 GB | 16 GB |
| Boot/OS | 64 GB SSD | 128 GB NVMe |
| NIC | 1 Gbps | 10 Gbps |

## 📁 Proje Yapısı

```
nextcloud-truenas/
├── setup.sh                       # 🆕 İnteraktif kurulum sihirbazı
├── README.md                      # Bu dosya
├── .install-config                # Kurulum yapılandırması (setup.sh tarafından oluşturulur)
├── docs/
│   ├── 01-truenas-setup.md       # TrueNAS kurulum rehberi
│   ├── 02-nextcloud-setup.md     # Nextcloud kurulum rehberi (AlmaLinux 10)
│   ├── 03-security-hardening.md  # Güvenlik yapılandırması
│   ├── 04-performance-tuning.md  # Performans optimizasyonu
│   └── 05-maintenance.md         # Bakım prosedürleri
├── docker/
│   ├── docker-compose.yml        # Ana Docker Compose
│   ├── docker-compose.override.yml # NPM için override (opsiyonel)
│   ├── .env                      # Environment değişkenleri (setup.sh tarafından oluşturulur)
│   ├── .env.example              # Ortam değişkenleri örneği
│   └── configs/
│       ├── nginx/
│       │   └── nextcloud.conf    # Nginx yapılandırması
│       ├── php/
│       │   └── custom.ini        # PHP ayarları
│       └── redis/
│           └── redis.conf        # Redis yapılandırması
├── scripts/
│   ├── 01-prepare-host.sh        # AlmaLinux host hazırlık scripti
│   ├── 02-mount-nfs.sh           # NFS mount scripti
│   ├── 03-deploy.sh              # Deployment scripti
│   ├── backup.sh                 # Yedekleme scripti
│   └── health-check.sh           # Sağlık kontrolü
└── configs/
    └── nextcloud-config.php      # Nextcloud config örneği
```

## 🚀 Kurulum Yöntemleri

### Yöntem 1: İnteraktif Kurulum (Önerilen)

```bash
# İnteraktif sihirbazı başlat
./setup.sh

# Sihirbaz sorulara cevap verdikten sonra kurulumu başlatacak
```

### Yöntem 2: Manuel Kurulum

#### 1. TrueNAS Kurulumu
[TrueNAS Kurulum Rehberi](docs/01-truenas-setup.md)

#### 2. Nextcloud Sunucusu Hazırlığı (AlmaLinux 10)
```bash
# Host'u hazırla
sudo ./scripts/01-prepare-host.sh

# NFS'i mount et
sudo ./scripts/02-mount-nfs.sh

# .env dosyasını düzenle
cp docker/.env.example docker/.env
nano docker/.env

# Deploy et
./scripts/03-deploy.sh
```

### Setup.sh Komut Satırı Seçenekleri

```bash
./setup.sh              # İnteraktif menü
./setup.sh --help       # Yardım
./setup.sh --config     # Sadece yapılandırma topla
./setup.sh --generate   # Sadece dosyaları oluştur
./setup.sh --install    # Mevcut yapılandırma ile kurulum başlat
./setup.sh --show       # Mevcut yapılandırmayı göster
./setup.sh --reset      # Yapılandırmayı sıfırla
```

### 3. İlk Erişim
- URL: https://cloud.yourdomain.com (domain kullanıyorsanız)
- URL: http://server-ip (doğrudan erişim)
- Admin kullanıcısı: Kurulum sihirbazında belirlenen değer

## 📋 Proje Fazları

| Faz | Açıklama | Süre | Durum |
|-----|----------|------|-------|
| 1 | Altyapı Kurulumu | 2-3 gün | ⬜ |
| 2 | Bulut Entegrasyonu | 2-3 gün | ⬜ |
| 3 | PoC ve Testler | 1-2 gün | ⬜ |
| 4 | Veri Entegrasyonu | 1-2 gün | ⬜ |
| 5 | Performans Tuning | 1-2 gün | ⬜ |
| 6 | Teslim ve Eğitim | 1 gün | ⬜ |

## 🔐 Güvenlik

- ✅ TLS 1.3 ile HTTPS
- ✅ Fail2ban brute-force koruması
- ✅ Firewalld yapılandırması
- ✅ SELinux desteği
- ✅ 2FA desteği
- ✅ Şifreli veri transferi (NFS over TLS opsiyonel)

## 📞 Destek

Herhangi bir sorun için issue açın veya dokümantasyonu inceleyin.

---

**Versiyon:** 1.0.0  
**Son Güncelleme:** Ocak 2026  
**Platform:** AlmaLinux 10
