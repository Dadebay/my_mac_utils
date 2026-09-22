# 014 — Sistem Verisi Doğruluğu ve Arka Plan Toplama

- **Status:** READY FOR IMPLEMENTATION
- **Hedef uygulayıcı:** Claude Opus
- **Öncelik:** Yüksek
- **Kapsam:** Bellek doğruluğu, arka planda ağ geçmişi, güvenli/kapsamlı disk taraması
- **Dil:** Kod yorumları ve kullanıcı metinleri Türkçe/İngilizce/Rusça mevcut `L10n.s` düzenini korumalı

## Uygulayıcıya önemli çalışma kuralı

Çalışma ağacı kirli. Kullanıcıya ait mevcut değişiklikleri geri alma, yeniden biçimlendirme veya kapsam dışı dosyalara yayma. Özellikle aşağıdaki dosyalarda mevcut kullanıcı değişiklikleri var; yeni işi onların üzerine dikkatle ekle:

- `Sources/macOS/SystemMonitor/SystemMonitorController.swift`
- `Sources/macOS/Panel/PanelMemoryView.swift`
- `Sources/macOS/Panel/PanelSystemStatView.swift`
- `Sources/GlassDoKit/Services/LocalizationManager.swift`

Başlamadan önce `git status --short` ve hedef dosyaların `git diff` çıktısını oku. `git reset`, `git checkout --` veya başka yıkıcı geri alma komutu kullanma.

---

## 1. Bellek hesaplarını tek ve doğru kaynağa bağla

### Gözlenen hata

Aynı makinede, aynı anda iki farklı kenar paneli iki farklı RAM kullanımı gösteriyor:

- Ayrı RAM paneli: yaklaşık **18,46 GiB / 24 GiB — %76,9**
- İşlemci panelindeki RAM özeti: yaklaşık **16,63 GiB / 24 GiB — %69,3**
- Fark: yaklaşık **1,83 GiB / 7,6 yüzde puanı**

Sebep iki ayrı formül:

1. `SystemMonitorController.systemMemory()`:
   `internal_page_count - purgeable_count + wire_count + compressor_page_count`
2. `SystemSampler.memoryStats()`:
   `active_count + wire_count + compressor_page_count`

`active_count`, yalnız yakın zamanda etkin olan sayfaları temsil eder; Etkinlik İzleyicisi'ndeki “Uygulama Belleği” yerine kullanılamaz. İkinci formül bu yüzden daha düşük sonuç üretiyor.

### Hedef

RAM paneli, işlemci içindeki RAM özeti, ana sistem kartı, menü çubuğu ve widget aynı `MemoryStats` örneğini ve aynı formülü kullanmalı.

### Önerilen uygulama

#### 1.1 `MemoryStats` modelini açık hâle getir

Dosya: `Sources/Shared/SystemStats.swift`

- `active` yerine gerçek anlamı taşıyan `appMemory` alanı kullan.
- `used` hesabı:

  ```swift
  appMemory + wired + compressed
  ```

- Eski widget snapshot JSON dosyaları bozulmamalı. `MemoryStats` için özel `Codable` uygula:
  - Yeni snapshot `appMemory` anahtarını yazsın.
  - Okurken önce `appMemory`, yoksa eski `active` anahtarını denesin.
  - Diğer bütün alanlar eksikse mevcut varsayılanlarına düşsün.
- Sırf uyumluluk için uygulama kodunda anlamı yanlış `active` adını kullanmaya devam etme.
- `init()` varsayılan kurucusunu koru; mevcut `MemoryStats()` çağrıları derlenmeli.

#### 1.2 Tek örnekleyici kullan

Dosya: `Sources/Shared/SystemSampler.swift`

`memoryStats()` içinde:

```text
appMemory = max(internal_page_count - purgeable_count, 0) × pageSize
wired = wire_count × pageSize
compressed = compressor_page_count × pageSize
cached = (external_page_count + purgeable_count) × pageSize
free = free_count × pageSize
used = appMemory + wired + compressed
```

Taşma/negatif korumasını koru. `UInt64` çıkarmasını doğrudan yapma; önce büyüklük karşılaştır.

Dosya: `Sources/macOS/SystemMonitor/SystemMonitorController.swift`

- Yerel `SystemMemoryStats` kopyasını ve `systemMemory()` fonksiyonunu kaldır.
- `private(set) var memory = MemoryStats()` kullan.
- Yenilemede `memory = SystemSampler.memoryStats()` çağır.
- Süreç listesi ve kullanıcıya ait mevcut `actionMessage`/sonlandırma değişikliklerine dokunma.

Bu değişiklikten sonra sistem belleği hesabının tek sahibi `SystemSampler` olmalı.

#### 1.3 Bütün tüketicileri güncelle

Aşağıdaki yerlerde `active` yerine `appMemory` kullan ve kullanıcı etiketini “Etkin/Active” değil “Uygulamalar/Apps” yap:

- `Sources/macOS/SystemMonitor/SystemStatsController.swift`
- `Sources/macOS/SystemMonitor/SystemCardViews.swift`
- `Sources/macOS/Panel/PanelSystemStatView.swift`
- `Sources/Widgets/SystemWidgetViews.swift`
- `Sources/Widgets/SystemOverviewWidgetView.swift`
- `Sources/Widgets/SystemProvider.swift` içindeki placeholder
- Snapshot/history taşıyan diğer bütün yerler (`rg -n "memory\.active|\.active"` ile doğrula)

Grafik geçmişindeki ilk katman da `appMemory / total` olmalı.

### Sahte “Bellek Baskısı %” değerini kaldır

Mevcut `pressureFraction` şu hesabı yapıyor:

```text
(wired + compressed) / total
```

Bu, macOS Memory Pressure değildir. macOS gerçek baskıyı tek, herkese açık ve senkron bir yüzde olarak yayımlamaz. Bu yüzden:

- Bu değeri kullanıcıya “Baskı/Pressure” adıyla gösterme.
- `memory_pressure` adlı shell aracını uygulama içinden çalıştırma.
- Özel/private API veya uydurma eşiklerle sahte yüzde üretme.

Tercih edilen dar çözüm:

- `pressureFraction` alanını kaldır veya yalnız geriye dönük decode için sakla ama UI'da kullanma.
- Karttaki hap/alt başlıkta istenirse kesin olarak bilinen değeri göster:
  - Etiket: “Çivilenmiş + sıkıştırılmış / Wired + compressed”
  - Değer: bayt veya toplam RAM içindeki pay
- Bellek kartı renklerini `usedFraction` üzerinden ve açıkça “kullanım” anlamıyla belirle.
- Menü çubuğundaki kalıcı enum raw değeri `memoryPressureChart` kullanıcı tercihlerini bozmamak için korunabilir; fakat kullanıcıya görünen adı “Kullanım geçmişi / Usage history” olmalı. Grafik zaten `memory.history` toplamını gösteriyor.

Gerçek basınç seviyesi ayrıca istenirse ikinci aşamada `DispatchSource.makeMemoryPressureSource` ile `.normal/.warning/.critical` enumu olarak canlı uygulamada izlenebilir. Bunu yüzdeye çevirme. Widget'ın tek seferlik örneklemesinde bu sinyalin güvenilir başlangıç değeri olmadığı için bu görevde zorunlu değil.

### Bellek testleri

Yeni Swift Testing testleri ekle:

1. `used == appMemory + wired + compressed`
2. `usedFraction` doğru ve `total == 0` durumunda sıfır
3. Eski JSON'daki `active` anahtarı `appMemory` olarak okunuyor
4. Yeni JSON `appMemory` yazıyor ve round-trip kayıpsız
5. Eksik alanlı eski snapshot tamamen çökmüyor
6. Saf bir yardımcı çıkarılırsa VM sayaç fixture'ı üzerinden `internal - purgeable` hesabı

### Bellek kabul ölçütleri

- Ayrı RAM paneli ile işlemci panelindeki RAM yüzdesi aynı yenileme aralığında en fazla biçimlendirme yuvarlaması kadar farklı.
- Widget ve menü çubuğu aynı `used` tanımını kullanıyor.
- UI'da “Bellek Baskısı %” yazmıyor.
- Eski `system-snapshot.json` okunabiliyor.
- İlgili testler geçiyor.

---

## 2. Ağ geçmişini GlassDo kapalıyken de toplat

### Önemli: altyapının büyük kısmı zaten var

Yeniden sıfırdan ajan yazma. Şunlar mevcut:

- `Sources/NetworkAgent/main.swift`
- `Sources/macOS/SystemMonitor/NetworkAgentController.swift`
- `Sources/Shared/NetworkAgentSettings.swift`
- `Sources/Shared/NetworkHistoryPersistence.swift`
- `Config/GlassDoNetworkAgent.plist`
- `project.yml` içindeki embed post-build adımı

Mevcut ajan `SMAppService.agent`, `launchd`, `RunAtLoad`, `KeepAlive` ve 5 saniyelik örnekleme kullanıyor. Ana uygulama kapalıyken çalışma amacı zaten kodda mevcut.

### Mevcut eksikler

1. Ayarlar > Ağ sayfası yalnız “GlassDo çalışırken birikir” notunu ve sıfırlama düğmesini gösteriyor. `NetworkAgentController` kullanıcı arayüzüne bağlanmamış.
2. `NetworkHistoryPersistence` dosyayı normal `.applicationSupportDirectory/GlassDo` altına yazıyor. Debug'da uygulama ve ajan aynı yeri görebilir; App Store Release sandbox'ında ana uygulama farklı bir container görebilir. Bu durumda ajan ve uygulama iki farklı geçmiş dosyasına yazabilir/okuyabilir.
3. Paneldeki geçmiş açıklaması ajan açık olsa bile daima “yalnız GlassDo çalışırken” diyor.

### Hedef mimari

```text
Fiziksel en* sayaçları
        │
        ▼
GlassDoNetworkAgent (tek yazıcı, 5 sn)
        │
        ▼
App Group/network-history.json
        │
        ├── GlassDo uygulaması (salt okur)
        └── Widget snapshot yayını
```

### Uygulama adımları

#### 2.1 Geçmiş dosyasını App Group'a taşı

Dosya: `Sources/Shared/NetworkHistoryPersistence.swift`

- Birincil dosya kökü olarak `SystemSnapshotStore.containerURL` kullan.
- Önerilen yol:

  ```text
  <App Group>/Library/Application Support/GlassDo/network-history.json
  ```

- Dizin atomik ve güvenli biçimde oluşturulsun.
- Eski konumdan tek seferlik göç uygula:
  1. Yeni dosya varsa onu kullan.
  2. Yeni dosya yok, eski dosya varsa decode et.
  3. Yeni konuma atomik yaz.
  4. Başarılı yazma doğrulanmadan eski dosyayı silme.
  5. Silmek zorunlu değil; eski dosyayı `.migrated` adıyla bırakmak daha güvenli.
- App Group container alınamazsa sessizce iki farklı konuma düşme. Açık bir unavailable durumu/log üret; veri bölünmesi gizlenmemeli.

Hem uygulama hem ajan aynı `NetworkHistoryPersistence` kodunu derlediği için bu değişiklik tek noktadan ikisini düzeltmeli.

#### 2.2 Ayarlar anahtarını bağla

Dosya: `Sources/macOS/Settings/SettingsView.swift`, `NetworkSettingsSection`

- `NetworkAgentController.shared` durumunu gözlemle.
- “GlassDo kapalıyken de ağ geçmişini tut” anahtarı ekle.
- Toggle değişince `setEnabled(_:)` çağır.
- Sayfa açılınca `refreshStatus()` çağır.
- `SMAppService.Status` durumlarını açık göster:
  - `.enabled`: arka plan toplama etkin
  - `.notRegistered`: kapalı
  - `.requiresApproval`: Sistem Ayarları onayı gerekiyor
  - `.notFound`: gömülü ajan bulunamadı; build/embed problemi
- `.requiresApproval` durumunda `openLoginItemsSettings()` düğmesi göster.
- `lastError` varsa kullanıcıya göster; toggle açık görünüp servis kapalı kalmamalı.

#### 2.3 Metinleri doğru duruma bağla

- Ajan açık ve gerçekten `.enabled` ise:
  “Geçmiş, GlassDo kapalıyken de arka planda birikir.”
- Ajan kapalıysa:
  “Geçmiş yalnızca GlassDo çalışırken birikir.”
- `.requiresApproval` durumunda “arka planda birikir” iddiasında bulunma.
- `PanelNetworkView` ve Ayarlar sayfası aynı gerçeği söylemeli.

#### 2.4 Tek yazıcı kuralını koru

- Ajan `.enabled` iken yalnız ajan `ingest`/`flush` yapmalı; ana uygulama yalnız `reload` etmeli.
- Ajan kapatılırken SIGTERM handler son veriyi flush etmeli.
- Toggle yarışlarında iki yazıcı oluşmadığını test et.
- Reset işlemi ajan açıkken dosya yarışına girebilir. Reset için kısa bir koordinasyon mekanizması ekle:
  - Tercihen App Group içinde reset generation/token,
  - veya ajanı geçici durdur → reset → yeniden kaydet.
- Dosya yazımı atomik kalmalı.

### Gerçekçi doğruluk sınırı

macOS geçmiş günler için resmi, geriye dönük “uygulama internet toplamı” sağlamaz. Ajan kurulmadan önceki trafik geri getirilemez. Uyku, güç kesintisi ve ilk baseline arasında ölçülemeyen kısa aralıklar olabilir. UI bunu “kurulumdan sonra ölçülen” veri olarak anlatmalı.

### Ağ testleri ve manuel doğrulama

- App Group yol seçimi testi: yeni yol kullanılıyor.
- Eski dosya → yeni dosya göç testi.
- Göç sırasında bozuk JSON yeni dosyayı ezmiyor.
- Ajan açıkken ana uygulama `ingest` etmiyor.
- Toggle kapat/aç sonrası status doğru.
- Uygulamayı Cmd+Q ile kapat; 2–3 dakika trafik üret; yeniden açınca “Bugün” artmış olmalı.
- Mac'i uyut/uyandır; devasa sahte delta oluşmamalı.
- VPN açıkken trafik iki kez sayılmamalı.
- Debug ve sandbox'lı Release yapısında aynı App Group dosyası okunmalı.

### Ağ kabul ölçütleri

- Kullanıcı ayarlardan arka plan toplamayı açabiliyor.
- Gerekli macOS onayına doğrudan yönlendiriliyor.
- GlassDo tamamen kapalıyken günlük toplam artıyor.
- Uygulama ve ajan aynı App Group dosyasını kullanıyor.
- Aynı bayt iki kez yazılmıyor.
- Paneldeki açıklama gerçek servis durumuyla uyumlu.

---

## 3. “En Büyük Uygulamalar” ve kapsamlı disk taraması

### Mevcut davranış

Dosya: `Sources/macOS/SystemMonitor/DiskSpaceAnalyzer.swift`

Şu anda:

- Yalnız kullanıcı ana klasörü ve `/Applications` taranıyor.
- Gizli öğeler atlanıyor.
- Tekil dosyalar listelenmiyor.
- `.app` ve `isPackage == true` paketleri aynı aday listesine girebiliyor.
- Bu yüzden başlık “En Büyük Uygulamalar” olsa da sonuç tam uygulama listesi veya tam disk analizi değil.

### Ürün kararı: iki ayrı liste yap

“En Büyük Uygulamalar” ile “En Büyük Dosya ve Klasörler” aynı şey değil. Tek listeye karıştırma.

#### Liste A — En Büyük Uygulamalar

App Store uyumlu ve düşük riskli:

- Kökler:
  - `/Applications`
  - `~/Applications`
  - `/System/Applications` (salt okunur, silme kapalı)
  - Varsa `/System/Cryptexes/App/System/Applications` (salt okunur)
- Yalnız `.app` paketlerini kabul et.
- `.photoslibrary`, `.xcodeproj`, `.framework`, arşiv ve başka genel paketleri uygulama listesine alma.
- Sistem uygulamalarında Çöp Kutusu düğmesi gösterme.
- Kullanıcı uygulamalarında mevcut onay + `NSWorkspace.recycle` davranışını koru.

#### Liste B — En Büyük Dosya ve Klasörler

Yeni, ayrı bölüm/sekme:

- App Store Release için kullanıcıdan `NSOpenPanel` ile taranacak klasörü seçmesini iste.
- Security-scoped bookmark kaydet; sonraki taramada `startAccessingSecurityScopedResource()` / `stopAccessing...` çiftini `defer` ile yönet.
- Kullanıcı ana klasörü veya Data volume seçmediyse “tüm disk tarandı” deme.
- Doğrudan dağıtılan sandbox'sız yapı için isteğe bağlı Full Disk Access açıklaması sunulabilir; macOS izni uygulama tarafından otomatik verilemez.
- App Store sandbox'ında kök diski izinsiz dolaşmaya veya ayrıcalık yükseltmeye çalışma.

### Tarama motoru kuralları

- Tarama ana aktörde çalışmasın.
- İptal desteklensin; panel kapanınca veya yeni tarama başlayınca eski iş durabilsin.
- Her dosyanın URL'sini bellekte tutma; yalnız top-N adayları min-heap/sınırlı sıralı koleksiyonda tut.
- Symlink takip etme.
- Seçilen volume dışına mount geçişi yapma.
- `/System/Volumes/Data/Volumes`, Time Machine snapshot/mount noktaları ve döngü oluşturabilecek kökleri atla.
- Paket bir kez toplam boyutuyla sayılıyorsa alt öğelerini ayrıca sayma.
- Boyut için mantıksal `fileSize` değil, disk kullanımını temsil eden `totalFileAllocatedSize`/`fileAllocatedSize` kullan.
- Hard link/APFS clone nedeniyle “dosyaların toplamı” ile Finder disk kullanımının birebir eşit olmayacağını UI'da belirt.
- İzin verilmeyen yolları sessizce yok sayıp “tamamlandı” deme; kısmi sonuç + erişilemeyen kapsam özeti göster.
- Tarama ilerlemesi en azından “taranan öğe sayısı + mevcut kök” olarak yayımlansın.
- Silme varsayılan olarak kapalı olsun; yalnız kullanıcı tarafından seçilmiş, yazılabilir ve sistem dışı hedeflerde mevcut Çöp Kutusu onayı açılsın.

### Önerilen model ayrımı

```text
DiskCapacityStats       → volume total/used/free (mevcut SystemSampler)
ApplicationSizeScanner  → yalnız .app paketleri
StorageScopeScanner     → kullanıcının seçtiği klasörde dosya/klasör top-N
StorageCandidate        → kaynak türü + erişim/silme yeteneği + allocated size
```

Kapasite ölçümünü tarama sonucuyla karıştırma. APFS volume kullanılan alanı `SystemSampler.diskStats()` vermeye devam etsin.

### Disk testleri

Geçici klasör fixture'larıyla:

1. `.app` paketi uygulama listesine girer.
2. `.photoslibrary` “uygulama” listesine girmez.
3. Tekil büyük dosya “Dosya ve Klasörler” listesine girer.
4. Symlink takip edilmez.
5. Paket hem kendisi hem çocukları olarak iki kez sayılmaz.
6. Top-N sınırı doğru sıralanır.
7. İptal taramayı erken bitirir ve eski sonuç yeni taramayı ezmez.
8. İzin hatası kısmi sonuç durumuna yansır.
9. Sistem uygulamasında silme yeteneği false.
10. Security-scoped access her çıkış yolunda kapatılır.

### Disk kabul ölçütleri

- “En Büyük Uygulamalar” gerçekten yalnız uygulamaları gösteriyor.
- Kullanıcı ayrı bir akıştan seçtiği kapsamın en büyük dosya/klasörlerini görebiliyor.
- UI hiçbir zaman erişemediği alanlar için “tüm disk tarandı” demiyor.
- Tarama UI'ı kilitlemiyor, iptal edilebiliyor ve izin hatalarını açıklıyor.
- Sistem/korumalı öğelerde silme sunulmuyor.

---

## Uygulama sırası

1. Bellek modelini ve Codable göçünü tamamla.
2. Bütün bellek tüketicilerini aynı modele geçir; bellek testlerini çalıştır.
3. Network history dosyasını App Group'a taşı ve göç testlerini ekle.
4. Ayarlar toggle/status/onay akışını bağla; gerçek kapalı-uygulama testi yap.
5. Uygulama tarayıcısını yalnız `.app` olacak şekilde düzelt.
6. Ayrı kullanıcı-seçimli kapsam tarayıcısını ekle.
7. Tam build ve manuel kabul kontrolü.

Her aşamayı ayrı, küçük commit olarak tutmak önerilir; kullanıcı özellikle istemedikçe mevcut kirli değişiklikleri commit'e dahil etme.

## Doğrulama komutları

Önce odaklı testler, sonra tam hedef:

```bash
xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS \
  -configuration Debug -derivedDataPath build/DerivedData \
  test -only-testing:GlassDoKitTests

xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS \
  -configuration Debug -derivedDataPath build/DerivedData build
```

Son olarak:

```bash
git diff --check
git status --short
```

## Bitti sayılma koşulu

- Bellek bütün yüzeylerde aynı değeri gösteriyor ve sahte pressure yüzdesi yok.
- Eski snapshot verisi okunuyor.
- Ağ ajanı kullanıcı tarafından yönetilebiliyor ve uygulama kapalıyken ölçüyor.
- Ağ geçmişi Debug ve sandbox'lı Release'te aynı App Group dosyasında.
- Disk UI'ı “uygulama” ile “dosya/klasör” sonuçlarını ayırıyor ve tarama kapsamını dürüstçe gösteriyor.
- Odaklı testler, tam build ve `git diff --check` geçiyor.

