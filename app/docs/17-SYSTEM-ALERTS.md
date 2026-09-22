# 17 — Sistem Uyarıları: Isınma ve Çöp Kutusu

> Güncellik: 2026-09-22
>
> İki bildirim: Mac ısındığında (ve mümkünse hangi uygulamanın ısıttığı) ve
> çöp kutusu eşiği geçtiğinde. Ayarlar > Sistem > Uyarılar.

## Kod

| Dosya | Görev |
|---|---|
| `Sources/macOS/Alerts/SystemAlertService.swift` | İki izleyici, bildirim gönderimi, tekrar kuralları |
| `Sources/macOS/Alerts/TopProcessSampler.swift` | İşlem başına CPU ölçümü (`libproc`) |
| `Sources/macOS/Alerts/SystemAlertSettings.swift` | Anahtarlar ve eşikler (`UserDefaults`) |
| `Sources/macOS/Alerts/AlertsSettingsSection.swift` | Ayarlar sayfası |

Servis `AppDelegate.applicationDidFinishLaunching`'de başlıyor — uyarılar
pencereye değil uygulamanın ömrüne bağlı.

## Isınma uyarısı

Her 30 saniyede bir bakılıyor. Eşik varsayılan **85 °C**: Apple Silicon'da
yoğun iş yükünde 70-80 °C normal çalışma aralığı, eşiği oraya koymak her
derlemede bildirim yağdırırdı.

Bildirim için sıcaklığın **üst üste iki ölçümde** (yaklaşık bir dakika)
eşiği geçmesi gerekiyor — tek seferlik sıçramalar (Spotlight dizinlemesi,
bir derleme) bildirim üretmiyor. Gönderimden sonra:

- 15 dakika yeni bildirim yok (`thermalCooldown`),
- ve sıcaklık eşiğin **8 °C altına** inmeden uyarı durumu kapanmıyor
  (histerezis). İkisi olmadan eşiğin etrafında salınan bir sıcaklık her
  turda yeni bildirim üretirdi.

Sıcaklık okunamazsa (`CPUTemperature.current()` nil) ölçüt sistemin kendi
`thermalState`'i oluyor: sayı yok ama "ısındı" bilgisi yine doğru.

### Suçlu işlem

`proc_pid_rusage` her işlemin biriktirdiği CPU süresini veriyor; iki örnek
arasındaki fark yüzdeyi çıkarıyor. `ps` çalıştırmak daha kısa olurdu ama
sandbox alt süreç açmaya izin vermiyor.

**Birim tuzağı — ölçüldü:** `ri_user_time`/`ri_system_time` nanosaniye
değil, mach zaman birimi. Ham farkı doğrudan saniyeye çevirince %100 CPU
yiyen bir işlem **%2,4** görünüyordu; `mach_timebase_info` (Apple
Silicon'da 125/3 ≈ 41,67) ile çarpınca %99,9. Ölçüm `yes > /dev/null` ile
iki koşu üzerinde doğrulandı.

Ölçek Activity Monitor'ünkiyle aynı: tek çekirdeğin tamamı = %100, çok
çekirdekli bir işlem (ör. `ollama`) 15 çekirdekli bir Mac'te %1400'e kadar
çıkabiliyor. %5 altı işlemler listelenmiyor — onlarca yardımcı süreç
sürekli %1-2 dolaşıyor.

## Çöp kutusu uyarısı

6 saatte bir `~/.Trash` ölçülüyor; eşik varsayılan **5 GB**.

Boy hesabı **diskte gerçekten kaplanan yer** (`totalFileAllocatedSize`)
üzerinden: mantıksal boyut seyrek ve sıkıştırılmış dosyalarda yalan
söylüyor, kullanıcı ise "boşaltınca ne kazanacağım" diye bakıyor.
Doğrulandı: 100 MB'lık seyrek bir dosya + 7 MB gerçek veri içeren bir
klasörde ölçüm 7.356.416 bayt, `du -sk` 7184 KB — **bire bir aynı**.

Aynı çöp için yeniden bildirim: ya **bir hafta** geçmeli ya da boy **yarı
yarıya** büyümeli. Kullanıcı "şimdi değil" dediyse bu bir karar; ertesi gün
aynı bildirimi göstermek kararı yok saymak olurdu.

### Neden "Boşalt" düğmesi yok

Bildirimdeki düğme çöp kutusunu **Finder'da açıyor**, boşaltmıyor. İki
sebep:

1. Geri alınamaz bir silmeyi, ne silineceği görülmeden bildirimden tek tık
   uzağa koymak doğru değil.
2. Sandbox'lı yapıda uygulamanın `~/.Trash`'e erişimi zaten yok —
   "Boşalt" düğmesi mağaza sürümünde sessizce hiçbir şey yapmayan bir
   düğme olurdu.

## App Sandbox sınırı (ölçüldü)

Release yapılandırması App Sandbox kullanıyor (`project.yml`). Sandbox
entitlement'ı taşıyan bir `.app` paketiyle sınandı:

| | Sandbox'sız (Debug, doğrudan dağıtım) | Sandbox'lı (Release / App Store) |
|---|---|---|
| `proc_listallpids` | 139 işlem, ~109'u okunabilir (kalanı root) | **0 işlem** |
| `~/.Trash` listeleme | çalışıyor | **çalışmıyor** |
| `ProcessInfo.thermalState` | çalışıyor | çalışıyor |

Sonuç:

- **Isınma uyarısı** her iki yapıda da geliyor; sandbox'lı yapıda suçlu
  uygulamanın adını yazamıyor ve bunu bildirimde açıkça söylüyor
  ("bu sürümde okunamıyor, Activity Monitor açın") — "baskın işlem
  bulunamadı" demek yanlış olurdu, aranamadı.
- **Çöp uyarısı** sandbox'lı yapıda hiç çalışmıyor. `isTrashReadable`
  false dönünce izleyici hiç başlamıyor ve Ayarlar sayfası bunu turuncu
  bir uyarı satırıyla yazıyor. Sessizce çalışmayan bir anahtar, kapalı bir
  anahtardan daha kötü: kullanıcı açtığını sanıp bildirim bekler.

### Mağaza sürümü için ne gerekir

- **Çöp:** kullanıcının bir kez `~/.Trash`'i `NSOpenPanel` ile seçmesi ve
  app-scope yer imiyle saklanması. Entitlement'lar (`user-selected.read-write`
  + `files.bookmarks.app-scope`) zaten var; eksik olan akış.
- **İşlem listesi:** App Store içinde bir yolu yok. Doğrudan dağıtılan
  (notarize edilmiş, sandbox'sız) sürümde çalışıyor.
