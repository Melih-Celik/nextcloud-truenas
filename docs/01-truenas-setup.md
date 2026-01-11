# TrueNAS SCALE Kurulum Rehberi

Bu döküman, 60TB kapasiteli TrueNAS SCALE storage sunucusunun kurulumunu anlatmaktadır.

## 📋 Ön Gereksinimler

- TrueNAS SCALE ISO (https://www.truenas.com/download-truenas-scale/)
- 8x 10TB HDD (NAS/Enterprise sınıfı)
- 2x SSD (Boot mirror için)
- 64GB ECC RAM
- Bootable USB

## 1️⃣ TrueNAS SCALE Kurulumu

### 1.1 Boot ve Kurulum

1. TrueNAS SCALE ISO'yu USB'ye yazın (Rufus, Etcher)
2. Sunucuyu USB'den boot edin
3. "Install/Upgrade" seçin
4. Boot disk olarak 2 SSD'yi seçin (Mirror)
5. Admin şifresini belirleyin
6. Kurulumun tamamlanmasını bekleyin
7. Yeniden başlatın

### 1.2 İlk Yapılandırma

Web arayüzüne erişin: `http://<truenas-ip>`

```
Default kullanıcı: admin (veya root)
Şifre: Kurulumda belirlediğiniz şifre
```

## 2️⃣ Network Yapılandırması

### 2.1 Statik IP Ayarı

1. **Network → Interfaces** menüsüne gidin
2. Ana interface'i seçin ve düzenleyin:

```yaml
Interface: enp0s3 (örnek)
IP Address: 192.168.1.20
Netmask: 24 (255.255.255.0)
```

3. **Network → Global Configuration**:

```yaml
Hostname: truenas
Domain: local
Default Gateway: 192.168.1.1
DNS Servers: 
  - 8.8.8.8
  - 8.8.4.4
```

## 3️⃣ ZFS Pool Oluşturma

### 3.1 Pool Yapılandırması

1. **Storage → Create Pool** menüsüne gidin
2. Pool adı: `storage`
3. Layout seçimi:

#### RAIDZ2 Yapılandırması (Önerilen)

```
Pool: storage
├── RAIDZ2 vdev
│   ├── disk1 (10TB)
│   ├── disk2 (10TB)
│   ├── disk3 (10TB)
│   ├── disk4 (10TB)
│   ├── disk5 (10TB)
│   ├── disk6 (10TB)
│   ├── disk7 (10TB)
│   └── disk8 (10TB)
├── SLOG (opsiyonel)
│   └── nvme0 (32GB Optane)
└── L2ARC (opsiyonel)
    └── nvme1 (512GB SSD)
```

| Yapılandırma | Toplam | Kullanılabilir | Tolerans |
|--------------|--------|----------------|----------|
| RAIDZ2 (8 disk) | 80TB | ~60TB | 2 disk |

### 3.2 Pool Oluşturma Adımları

1. Tüm 8 diski seçin
2. **Layout**: RAIDZ2
3. **Create Pool** butonuna tıklayın

### 3.3 CLI ile Pool Oluşturma (Alternatif)

```bash
# SSH ile bağlanın
ssh admin@192.168.1.20

# Pool oluştur
zpool create -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  storage raidz2 \
  /dev/sda /dev/sdb /dev/sdc /dev/sdd \
  /dev/sde /dev/sdf /dev/sdg /dev/sdh

# SLOG ekle (opsiyonel)
zpool add storage log /dev/nvme0n1

# L2ARC ekle (opsiyonel)
zpool add storage cache /dev/nvme1n1
```

## 4️⃣ Dataset Oluşturma

### 4.1 Nextcloud için Dataset Yapısı

**Storage → Datasets → Add Dataset**

```
storage/
├── nextcloud/                    # Ana Nextcloud dataset
│   ├── data/                     # Kullanıcı dosyaları (60TB)
│   │   ├── recordsize=1M
│   │   └── compression=lz4
│   ├── database/                 # PostgreSQL (NFS ile paylaşılmayacak)
│   │   ├── recordsize=16K
│   │   └── primarycache=metadata
│   └── config/                   # Nextcloud config
│       └── recordsize=128K
└── backup/                       # Yedekler için
```

### 4.2 CLI ile Dataset Oluşturma

```bash
# Ana dataset
zfs create storage/nextcloud

# Data dataset (büyük dosyalar için optimize)
zfs create -o recordsize=1M \
  -o compression=lz4 \
  -o atime=off \
  storage/nextcloud/data

# Config dataset
zfs create -o recordsize=128K \
  -o compression=lz4 \
  storage/nextcloud/config

# Backup dataset
zfs create -o compression=lz4 \
  storage/backup
```

### 4.3 Web UI ile Dataset Oluşturma

1. **Storage → storage pool → Add Dataset**
2. Her dataset için:

| Dataset | Record Size | Compression | Sync |
|---------|-------------|-------------|------|
| nextcloud | Inherit | lz4 | Standard |
| nextcloud/data | 1M | lz4 | Standard |
| nextcloud/config | 128K | lz4 | Standard |
| backup | Inherit | lz4 | Standard |

## 5️⃣ NFS Paylaşımı Yapılandırma

### 5.1 NFS Servisini Etkinleştir

1. **System Settings → Services** menüsüne gidin
2. **NFS** servisini bulun ve etkinleştirin
3. **Start Automatically** kutusunu işaretleyin
4. Servis ayarları için kalem ikonuna tıklayın:

```yaml
Number of threads: 16
Bind IP Addresses: 192.168.1.20
Enable NFSv4: ✓
NFSv3 ownership model for NFSv4: ✗
```

### 5.2 NFS Share Oluşturma

1. **Shares → Unix Shares (NFS) → Add**

#### Nextcloud Data Paylaşımı

```yaml
Path: /mnt/storage/nextcloud/data
Description: Nextcloud User Data
Enabled: ✓

Networks (Authorized Networks):
  - 192.168.1.10/32    # Sadece Nextcloud sunucusu

Hosts (Authorized Hosts):
  - 192.168.1.10       # Nextcloud sunucu IP'si

Maproot User: root
Maproot Group: wheel
```

#### Nextcloud Config Paylaşımı

```yaml
Path: /mnt/storage/nextcloud/config
Description: Nextcloud Config
Enabled: ✓

Networks:
  - 192.168.1.10/32

Maproot User: root
Maproot Group: wheel
```

### 5.3 CLI ile NFS Export

```bash
# /etc/exports dosyası otomatik oluşturulur
# Manuel kontrol için:
cat /etc/exports

# Beklenen çıktı:
# "/mnt/storage/nextcloud/data" 192.168.1.10(rw,sync,no_subtree_check,root_squash)
# "/mnt/storage/nextcloud/config" 192.168.1.10(rw,sync,no_subtree_check,root_squash)

# Export'ları yenile
exportfs -ra

# Aktif export'ları göster
exportfs -v
```

## 6️⃣ İzinler ve Kullanıcı Ayarları

### 6.1 Nextcloud için Kullanıcı Oluşturma

1. **Credentials → Local Users → Add**

```yaml
Username: nextcloud
Full Name: Nextcloud Service Account
Password: [güçlü şifre]
UID: 33        # www-data UID'si ile eşleşmeli
Primary Group: Create new primary group
Home Directory: /nonexistent
Shell: nologin
```

### 6.2 Dataset İzinleri

1. **Storage → storage/nextcloud/data → Edit Permissions**

```yaml
Owner: nextcloud (veya UID 33)
Owner Group: nextcloud (veya GID 33)
Access Mode: 770

Apply permissions recursively: ✓
```

### 6.3 CLI ile İzinler

```bash
# www-data kullanıcısı ile eşleşen UID/GID
chown -R 33:33 /mnt/storage/nextcloud/data
chown -R 33:33 /mnt/storage/nextcloud/config
chmod -R 770 /mnt/storage/nextcloud/data
chmod -R 770 /mnt/storage/nextcloud/config
```

## 7️⃣ Performans Ayarları

### 7.1 ZFS ARC Tuning

**System Settings → Advanced → Sysctl**

```bash
# ARC max boyutu (örnek: 48GB RAM'de 32GB ARC)
vfs.zfs.arc_max=34359738368

# L2ARC ayarları
vfs.zfs.l2arc_write_max=536870912
vfs.zfs.l2arc_headroom=12
```

### 7.2 NFS Performans

```bash
# /etc/nfs.conf ayarları (TrueNAS UI'dan)
[nfsd]
threads=16
tcp=y
vers3=n
vers4=y
vers4.0=y
vers4.1=y
vers4.2=y
```

## 8️⃣ Monitoring ve Alertler

### 8.1 SMART Monitoring

1. **Data Protection → S.M.A.R.T. Tests**
2. Her disk için haftalık Long test planla

### 8.2 Email Alertleri

1. **System Settings → Alert Settings**
2. Email yapılandır:

```yaml
SMTP Server: smtp.gmail.com
Port: 587
Security: TLS
Username: your-email@gmail.com
Password: app-password
From Email: truenas@yourdomain.com
To Email: admin@yourdomain.com
```

### 8.3 Scrub Schedule

1. **Data Protection → Scrub Tasks → Add**

```yaml
Pool: storage
Threshold Days: 7
Description: Weekly Scrub
Schedule: Weekly (Pazar 02:00)
```

## 9️⃣ Snapshot Politikası

### 9.1 Otomatik Snapshot

1. **Data Protection → Periodic Snapshot Tasks → Add**

```yaml
Dataset: storage/nextcloud/data
Recursive: ✓
Exclude Child Datasets: ✗
Snapshot Lifetime: 2 weeks
Naming Schema: auto-%Y-%m-%d_%H-%M
Schedule: Daily at 02:00
```

### 9.2 Retention Policy

| Snapshot Tipi | Saklama Süresi | Sıklık |
|---------------|----------------|--------|
| Saatlik | 24 saat | Her saat |
| Günlük | 7 gün | Her gün 02:00 |
| Haftalık | 4 hafta | Pazar 03:00 |
| Aylık | 12 ay | Ayın 1'i 04:00 |

## 🔍 Doğrulama

### NFS Export Kontrolü

```bash
# TrueNAS üzerinde
showmount -e localhost

# Beklenen çıktı:
# Export list for localhost:
# /mnt/storage/nextcloud/data   192.168.1.10
# /mnt/storage/nextcloud/config 192.168.1.10
```

### Pool Durumu

```bash
zpool status storage

# Beklenen: Tüm diskler ONLINE
```

### Dataset Listesi

```bash
zfs list -r storage/nextcloud

# Beklenen çıktı:
# NAME                        USED  AVAIL  REFER  MOUNTPOINT
# storage/nextcloud           100K  55.0T   100K  /mnt/storage/nextcloud
# storage/nextcloud/data      100K  55.0T   100K  /mnt/storage/nextcloud/data
# storage/nextcloud/config    100K  55.0T   100K  /mnt/storage/nextcloud/config
```

## ✅ Checklist

- [ ] TrueNAS SCALE kuruldu
- [ ] Statik IP yapılandırıldı
- [ ] ZFS pool oluşturuldu (RAIDZ2)
- [ ] Dataset'ler oluşturuldu
- [ ] NFS servisi etkinleştirildi
- [ ] NFS share'ler oluşturuldu
- [ ] İzinler ayarlandı
- [ ] SMART monitoring aktif
- [ ] Scrub schedule oluşturuldu
- [ ] Snapshot policy tanımlandı
- [ ] Email alertler yapılandırıldı

## ➡️ Sonraki Adım

TrueNAS kurulumu tamamlandıktan sonra [Nextcloud Kurulum Rehberi](02-nextcloud-setup.md)'ne geçin.
