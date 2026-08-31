# GlassDo

Sadece macOS için, tamamen yerel (SwiftData, sync yok) çalışan bir görev
yöneticisi. Ana pencerenin yanında, ekranın kenarına yaslanan **Liquid Glass**
bir panel de var — kenardan dışarı çekip görevlerini, sistem durumunu ve
notlarını odaktaki uygulamayı hiç değiştirmeden kontrol ediyorsun.

macOS 26'nın `.glassEffect` / `GlassEffectContainer` API'leriyle yazıldı;
cam efekti elle blur/opacity taklidi değil, gerçek zamanlı refraksiyon.

## Neler var

**Görev yönetimi**
- Proje/etiketle gruplama, öncelik, bitiş tarihi, çok satırlı not
- Akıllı listeler (Bugün / Yaklaşan / Tümü / Tamamlanan), arama, sürükle-bırak sıralama
- Tamamen yerel SwiftData store — arka planda hiçbir sunucuya konuşmuyor

**Kenar paneli (Edge Rail)**
- Ekranın herhangi bir kenarına yaslanan, hover'da açılan `NSPanel` tabanlı panel
- Rail ↔ genişletilmiş görünüm arasında geçiş, kenara gizlenme (sliver/peek) ve
  sabitleme (pinned) modları
- Rail ikonları arasında geçiş yaparken panel çerçevesi hiç oynamaz — yalnızca
  içerik ve seçim vurgusu kısa bir geçişle değişir

**Sistem izleme**
- CPU (çekirdek başına), bellek, disk, batarya, ağ hızı/günlük kullanım için
  canlı kartlar ve grafikler
- Aynı ölçümler menü çubuğunda da (`NSStatusItem`), istenen biçimde: çubuk,
  yüzde, bayt, grafik — kullanıcı hangi ölçeri hangi biçimde göreceğini seçiyor
- Ağ hız testi, disk alanı analizi, süreç bazlı ağ kullanımı

**Diğer**
- WidgetKit widget'ları (masaüstü/Notification Center) — bugünün görevleri ve
  sistem özeti
- Pencere değiştirici (Cmd+Tab benzeri overlay)
- Panelden koparılıp ekranda serbest duran not pencereleri (popped notes)
- Türkçe / İngilizce / Rusça arayüz

## Teknik

| | |
|---|---|
| Dil | Swift 6 (`SWIFT_STRICT_CONCURRENCY: complete`) |
| UI | SwiftUI + AppKit (panel/menü çubuğu entegrasyonu için) |
| Veri | SwiftData, tamamen yerel |
| Minimum sürüm | macOS 26 (Liquid Glass gerektiriyor) |
| Proje üretimi | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) |
| Test | Swift Testing (`@Test`) |

### Modüller

```
Sources/
├── GlassDoKit/     # Paylaşılan çekirdek: modeller, servisler, tasarım sistemi
├── Shared/         # Uygulama + widget uzantısı arasında paylaşılan ölçüm kodu
├── macOS/          # Ana uygulama: pencere, kenar paneli, menü çubuğu, ayarlar
└── Widgets/        # WidgetKit uzantısı
```

## Kurulum ve derleme

```bash
brew install xcodegen   # yalnızca ilk sefer
xcodegen generate
xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS \
  -configuration Debug build
```

`GlassDo.xcodeproj`, `project.yml`'den üretildiği için repoya dahil değil —
`xcodegen generate` her `project.yml` değişikliğinden sonra tekrar çalıştırılmalı.

## Durum

Aktif geliştirme aşamasında, tek kullanıcı için (kendi ihtiyacım). Planlama ve
teknik şartname dokümanları [`docs/`](docs/) klasöründe — okuma sırası ve
kapsam için [docs/README.md](docs/README.md)'ye bak.
