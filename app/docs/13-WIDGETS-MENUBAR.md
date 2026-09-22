# 13 — Widget'lar ve Menü Çubuğu Ölçerleri

Sistem ölçümlerinin uygulama penceresinin dışına taşındığı iki yüzey:
**macOS widget'ları** (masaüstü + Bildirim Merkezi) ve **menü çubuğu
ölçerleri**.

---

## Neden iki ayrı yüzey

Aynı sayılar, iki farklı soru için:

- **Widget** — "bugün ne kadar veri harcadım, disk ne durumda?" Nadiren
  bakılır, geniş yer vardır, beş dakikalık tazelik yeter.
- **Menü çubuğu** — "şu an ne oluyor?" Sürekli göz ucuyla bakılır, yer
  yoktur, iki saniyelik tazelik gerekir.

Bu yüzden ikisi aynı ölçümü paylaşır ama aynı kodu çizmez.

---

## Veri akışı

```
                    SystemSampler (Sources/Shared)
                   çekirdek sayaçları, IORegistry, IOHID
                              │
            ┌─────────────────┴──────────────────┐
            │                                    │
   SystemStatsController                  SystemProvider
   (uygulama, 2 sn)                       (widget uzantısı, ~5 dk)
            │                                    │
   menü çubuğu + pano              anlık görüntüyü okur, üstüne
            │                      kendi ölçtüklerini yazar
            └──────► system-snapshot.json ───────┘
                     (App Group kapsayıcısı)
```

**Neden anlık görüntü var:** widget uzantısı kum havuzunda çalışır ve
iki şeyi kendi başına üretemez:

1. **Sıcaklık** — IOHID sensörlerine kum havuzundan erişilemiyor.
2. **"Bugün / son 30 gün" ağ toplamları** — çekirdeğin arayüz sayaçları
   her yeniden başlatmada sıfırlanır; bu toplamlar yalnızca uygulama
   çalışırken biriktirilebiliyor (bkz. `NetworkHistoryStore`).

Bellek, disk, batarya ve çalışma süresi tek örnekle okunabildiği için
widget bunları **kendisi** ölçer — GlassDo hiç açık değilken bile taze
kalırlar. Uygulama hiç çalışmadıysa sıcaklık ve ağ toplamları boş görünür,
kart ölü görünmez.

**App Group:** `V793RH49BX.group.com.dadebay.glassdo`

Takım öneki zorunlu: uygulama kum havuzunda değil, uzantı ise (WidgetKit
gereği) kum havuzunda. macOS'ta iki tarafın aynı klasörü görmesinin başka
yolu yok.

---

## Widget'lar

`Sources/Widgets` · hedef: `GlassDoWidgets` (app-extension)

| Widget | Boyutlar | İçerik |
|---|---|---|
| Disk | küçük, orta | Doluluk oranı, kalan yer, doluluğun seyri |
| Ağ Trafiği | küçük, orta | Bugün / dün / son 7 gün / son 30 gün |
| Batarya | küçük, orta | Şarj, sağlık, döngü, güç; kart doluluk kadar doluyor |
| Bellek | küçük, orta | Kullanılan RAM, dağılım, baskı rengi |
| İşlemci Sıcaklığı | küçük, orta | Derece, sıcaklık seyri, termal baskı |

Yenileme: `TimelineReloadPolicy.after(+5 dk)`. WidgetKit'in günlük yenileme
bütçesi sınırlı — uygulama da widget'ları en fazla beş dakikada bir
dürtüyor (`SystemStatsController.widgetReloadInterval`).

Ayarlar → **Widget'lar** sayfasındaki galeri, widget görünümlerinin
**kendisini** çiziyor (`forcedFamily` ile boyut elle veriliyor). Ayrı bir
önizleme çizilseydi widget değiştikçe önizleme yalan söylemeye başlardı.

---

## Menü çubuğu ölçerleri

`Sources/macOS/MenuBar` · 28 ölçer, altı grupta

| Grup | Ölçerler |
|---|---|
| İşlemci | yük çubuğu, yük yüzdesi, yük grafiği, sıcaklık çubuğu, sıcaklık derecesi |
| Bellek | çubuk, bayt, yüzde, takas, baskı grafiği |
| Disk | çubuk, halka, kullanılan bayt, yüzde, boş alan |
| Ağ | etkinlik (iki satır), indirme, yükleme, oklar, VPN, bugünkü veri |
| Batarya | simge, yüzde, güç, döngü, sağlık, kalan süre |
| Makine | çalışma süresi |

- `MenuBarExtra` değil `NSStatusItem` kullanılıyor: SwiftUI'nin
  `MenuBarExtra`'sı sahne düzeyinde tanımlanır ve sayısı derleme zamanında
  sabittir; buradaysa kullanıcı çalışırken ölçer ekleyip çıkarabiliyor.
- **Sol tık** → o grubun ayrıntılı kartı (panodaki kartın kendisi) bir
  popover'da açılır. **Sağ tık** → gizle / ayarlar / çık.
- Ölçüm döngüsü yalnızca en az bir ölçer görünürken çalışır; menü çubuğu
  boşken sistem yoklanmaz.
- Seçim `UserDefaults` → `menubar.enabledItems`, sıra korunur.

Ayarlar → **Menü Çubuğu** sayfasındaki galeri karoları ölçerin gerçek
çizimini **canlı** gösteriyor: menü çubuğuna eklemeden önce ne
görüneceğini görmek gerekiyor.

---

## Sıcaklık: kabul edilmiş maliyet

macOS işlemci sıcaklığını belgelenmiş hiçbir API'yle vermiyor.
`Sources/Shared/CPUTemperature.swift` iki özel yol kullanıyor:

- **Apple Silicon** — `IOHIDEventSystemClient*` sembolleri `dlsym` ile
  çözülüyor (başlıkta yayımlanmıyorlar). Sensör adları kuşağa göre
  değişiyor: `PMU tdie*` (M3/M4), `pACC`/`eACC MTR Temp Sensor` (M1/M2).
  En sıcak çekirdek sensörü gösteriliyor — "ne kadar ısındı" sorusunun
  cevabı ortalama değil tepe değer.
- **Intel** — `AppleSMC` üzerinden `TC0P` / `TC0D`.

Sonuçları:

- Bu kod **App Store'a giremez**.
- Bir macOS güncellemesi sembolleri ya da sensör adlarını değiştirirse
  ölçüm sessizce `nil`'e düşer; uygulama çökmez, yalnızca derece yerine
  termal baskı (`ProcessInfo.thermalState`) gösterilir.
- Anlamsız sensör değerleri (`PMU tdev*` sensörleri −9200 döndürüyor)
  0–130 °C aralığı dışında kaldıkları için eleniyor.

---

## Kapsam dışı

Referans uygulamada olup burada **olmayanlar** — hiçbirinin güvenilir bir
yolu yok:

- **Fan hızı** — Apple Silicon'da SMC fan anahtarları yok; fansız
  makinelerde zaten anlamsız.
- **GPU yükü** — belgelenmiş bir sayaç yok.
- **Bluetooth cihaz bataryası** — yalnızca bazı cihazlar bildiriyor,
  okuma yolu cihaz üreticisine göre değişiyor.

---

## Elle test listesi

1. **Widget ekleme** — masaüstüne sağ tık → "Widget'ları Düzenle" →
   GlassDo → beş widget da listede mi, ikisi de (küçük/orta) eklenebiliyor mu?
2. **Uygulama kapalıyken** — GlassDo'dan çık, widget'lar bellek/disk/batarya
   göstermeye devam ediyor mu? (Sıcaklık ve ağ toplamları donmuş olmalı.)
3. **Menü çubuğu** — Ayarlar → Menü Çubuğu'ndan birkaç ölçer seç; anında
   beliriyorlar mı, kaldırınca kayboluyorlar mı?
4. **Tıklama** — menü çubuğundaki ölçere sol tık kartı açıyor mu, sağ tık
   menüyü?
5. **Sıcaklık** — derece gösteriliyor mu? (Bu makinede IOHID okuması
   doğrulandı: `PMU tdie*` sensörleri, ~37 °C boşta.)
6. **Dil** — ayarlardan dili değiştirince menü çubuğu ve widget metinleri
   takip ediyor mu? (Widget'ta bir sonraki yenilemede.)
