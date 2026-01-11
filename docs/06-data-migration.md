# 📦 60TB Veri Aktarım Rehberi

Bu döküman, büyük miktarda veriyi Nextcloud'a aktarmak için çeşitli yöntemleri açıklamaktadır.

## 🎯 Önemli Bilgiler

- **Nextcloud veri dizini**: `/mnt/nextcloud-data/` (NFS mount - TrueNAS üzerinde)
- **Her kullanıcının dosyaları**: `/mnt/nextcloud-data/KULLANICI_ADI/files/`
- **www-data UID**: 82 (Alpine container)

## 🚀 Yöntem 1: Doğrudan NFS Kopyalama (EN HIZLI)

60TB gibi büyük veri setleri için en hızlı yöntem, veriyi doğrudan TrueNAS NFS paylaşımına kopyalamak ve ardından Nextcloud veritabanını güncellemektir.

### Adım 1: Kullanıcı Oluşturun

```bash
# Admin panelinden veya CLI ile kullanıcı oluşturun
docker exec -u www-data nextcloud php occ user:add kullanici_adi

# Veya toplu kullanıcı oluşturma
for user in ahmet mehmet ayse; do
    docker exec -u www-data nextcloud php occ user:add $user --password-from-env
done
```

### Adım 2: Veriyi Kopyalayın

```bash
# Kaynak dizinden hedef dizine kopyalama
# KULLANICI_ADI yerine gerçek kullanıcı adını yazın

rsync -avP --progress /kaynak/veri/ /mnt/nextcloud-data/KULLANICI_ADI/files/

# Örnek: ahmet kullanıcısına veri aktarma
rsync -avP --progress /mnt/eski-storage/ahmet-dosyalari/ /mnt/nextcloud-data/ahmet/files/
```

### Adım 3: İzinleri Düzeltin

```bash
# www-data (UID 82) sahipliğini ayarlayın
chown -R 82:82 /mnt/nextcloud-data/KULLANICI_ADI/files/

# Tüm kullanıcılar için
chown -R 82:82 /mnt/nextcloud-data/
```

### Adım 4: Veritabanını Güncelleyin

```bash
# Belirli kullanıcı için tarama
docker exec -u www-data nextcloud php occ files:scan KULLANICI_ADI

# Tüm kullanıcılar için tarama
docker exec -u www-data nextcloud php occ files:scan --all

# Veya script kullanın
./scripts/data-migration.sh --scan
```

## 🚀 Yöntem 2: TrueNAS Üzerinden Kopyalama (ÖNERİLEN)

TrueNAS sunucusuna SSH ile bağlanıp, veriyi doğrudan ZFS pool'a kopyalayabilirsiniz.

### TrueNAS'ta:

```bash
# TrueNAS'a SSH bağlantısı
ssh admin@192.168.1.20

# Veriyi doğrudan ZFS dataset'ine kopyalayın
rsync -avP /mnt/eski-pool/veriler/ /mnt/storage/nextcloud/data/admin/files/

# İzinleri ayarlayın
chown -R 82:82 /mnt/storage/nextcloud/data/
```

### Nextcloud Sunucusunda:

```bash
# Veritabanını güncelleyin
docker exec -u www-data nextcloud php occ files:scan --all
```

## 🚀 Yöntem 3: Veri Aktarım Scripti

Hazırladığımız script'i kullanabilirsiniz:

```bash
# Durumu kontrol edin
./scripts/data-migration.sh --status

# Belirli kullanıcıyı tarayın
./scripts/data-migration.sh --scan-user ahmet

# Tüm kullanıcıları tarayın
./scripts/data-migration.sh --scan
```

## 🚀 Yöntem 4: Nextcloud Web Arayüzü

Küçük dosyalar için web arayüzünden yükleme yapılabilir (önerilmez büyük veriler için).

## 🚀 Yöntem 5: Nextcloud Desktop Client

Desktop client ile senkronizasyon (yavaş olabilir).

## 📊 Büyük Veri Aktarım Stratejisi (60TB)

### Önerilen Yaklaşım:

1. **Paralel Kopyalama**: Birden fazla rsync işlemi çalıştırın
   ```bash
   # Terminal 1
   rsync -avP /kaynak/A-M/ /mnt/nextcloud-data/admin/files/A-M/
   
   # Terminal 2
   rsync -avP /kaynak/N-Z/ /mnt/nextcloud-data/admin/files/N-Z/
   ```

2. **Screen/Tmux Kullanın**: Uzun süren işlemler için
   ```bash
   screen -S veri-aktarim
   rsync -avP /kaynak/ /hedef/
   # Ctrl+A, D ile detach
   # screen -r veri-aktarim ile geri dönün
   ```

3. **İlerlemeyi Takip Edin**:
   ```bash
   # rsync ilerleme
   rsync -avP --info=progress2 /kaynak/ /hedef/
   
   # Disk kullanımını izleyin
   watch -n 10 'df -h /mnt/nextcloud-data'
   ```

4. **Bant Genişliğini Sınırlayın** (gerekirse):
   ```bash
   rsync -avP --bwlimit=100000 /kaynak/ /hedef/  # 100MB/s limit
   ```

## ⏱️ Tahmini Süreler

| Veri Boyutu | 1 Gbps Ağ | 10 Gbps Ağ |
|-------------|-----------|------------|
| 1 TB        | ~2.5 saat | ~15 dakika |
| 10 TB       | ~25 saat  | ~2.5 saat  |
| 60 TB       | ~6 gün    | ~15 saat   |

## 🔧 Sorun Giderme

### "Permission denied" hatası
```bash
# İzinleri kontrol edin
ls -la /mnt/nextcloud-data/
# Düzeltin
chown -R 82:82 /mnt/nextcloud-data/
```

### "Dosyalar görünmüyor" sorunu
```bash
# Veritabanını güncelleyin
docker exec -u www-data nextcloud php occ files:scan --all

# Önbelleği temizleyin
docker exec -u www-data nextcloud php occ files:cleanup
```

### Tarama çok yavaş
```bash
# Path tabanlı tarama yapın (daha hızlı)
docker exec -u www-data nextcloud php occ files:scan --path="/admin/files/yeni-klasor"
```

### Büyük dosya yükleme sorunu
```bash
# PHP ayarlarını kontrol edin
docker exec nextcloud php -i | grep -E "(upload_max|post_max|memory_limit)"
```

## 📝 Checklist

- [ ] Kullanıcılar oluşturuldu
- [ ] Veri kopyalandı
- [ ] İzinler düzeltildi (82:82)
- [ ] Veritabanı taraması yapıldı
- [ ] Dosyalar web arayüzünde görünüyor
- [ ] Yedekleme planı oluşturuldu

## 🔄 Kopyalama Sonrası Kontrol

```bash
# Disk kullanımını kontrol edin
df -h /mnt/nextcloud-data

# Kullanıcı kota kullanımını görün
docker exec -u www-data nextcloud php occ user:info admin

# Dosya sayısını kontrol edin
find /mnt/nextcloud-data -type f | wc -l
```
