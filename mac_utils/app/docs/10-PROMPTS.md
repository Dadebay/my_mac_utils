# 10 — Sonnet 5 İçin Hazır Promptlar

> **Kapsam güncellemesi:** iOS/iCloud/test-dağıtım fazları kaldırıldı. Güncel
> plan: [07-IMPLEMENTATION-PLAN.md](07-IMPLEMENTATION-PLAN.md) (7 faz, macOS-only).

Kullanım: her fazda ilgili promptu kopyala-yapıştır. **Faz bitmeden sonrakine geçme.**
Her fazdan sonra derle ve manuel olarak dene.

---

## Oturum açılış promptu (her yeni oturumda bir kez)

```
Bu projede macOS için "GlassDo" adında bir todo uygulaması geliştiriyoruz.
Tam şartname docs/ klasöründe. Şunları oku ve özetle, sonra dur:
docs/README.md, docs/01-TECH-STACK.md, docs/02-ARCHITECTURE.md,
docs/03-DATA-MODEL.md, docs/05-FLOATING-WIDGET.md, docs/07-IMPLEMENTATION-PLAN.md

Kurallar:
- Swift 6, strict concurrency açık, SwiftUI. Xcode 26 SDK, deployment macOS 26.
- Sadece macOS — iOS uygulaması, iCloud sync yok.
- Proje dosyası XcodeGen ile project.yml'den üretilir; .xcodeproj'u elle düzenleme.
- Kod yazmadan önce hangi dosyaları oluşturacağını listele.
- Her fazın sonunda `xcodebuild build` ile derlemeyi doğrula.
- Şartnamede olmayan özellik ekleme.
```

---

## Faz 1 — İskelet ✅ (tamamlandı, referans)

```
Faz 1'i uygula: proje iskeleti.

- docs/02-ARCHITECTURE.md içindeki project.yml şablonunu kullanarak
  proje kök dizininde project.yml oluştur (macOS-only).
- Klasör yapısını oluştur: Sources/GlassDoKit, Sources/macOS,
  Tests/GlassDoKitTests
- GlassDoKit'e boş bir public struct koy ki framework derlensin.
- macOS app: @main App, tek bir Window, "GlassDo" yazan bir Text.
- Her target'a info: path: .../Info.plist ekle (XcodeGen 2.46 tuzağı,
  bkz. docs/02-ARCHITECTURE.md).
- .gitignore ekle (Xcode + *.xcodeproj çünkü XcodeGen üretiyor).
- `xcodegen generate` çalıştır, şemayı derle ve sonucu göster.
```

---

## Faz 2 — Veri katmanı ✅ (tamamlandı, referans)

```
Faz 2'yi uygula: SwiftData modelleri.

docs/03-DATA-MODEL.md'i birebir uygula:
- Sources/GlassDoKit/Models/ altında Task, Project, Tag, Priority (public)
- Sources/GlassDoKit/Store/AppStore.swift — makeContainer(inMemory:),
  CloudKit YOK, tamamen yerel store
- Sources/GlassDoKit/Store/SeedData.swift — docs/11-SEED-DATA.md'deki
  7 proje ve görev listesi

Testler (Tests/GlassDoKitTests, Swift Testing framework'ü — XCTest değil):
- Görev oluşturma ve tamamlama
- todayPredicate filtresi (dueDate karşılaştırmasında force-unwrap KULLANMA,
  runtime'da crash eder — .flatMap kullan, bkz. docs/03-DATA-MODEL.md)
- Priority round-trip
- Seed data idempotency testi

`xcodebuild test -scheme GlassDo-macOS -destination 'platform=macOS'` çalıştır.
```

---

## Faz 3 — macOS ana pencere

```
Faz 3'ü uygula: macOS ana penceresi.

docs/04-FEATURES.md'deki "macOS ana pencere" şemasına göre:
- NavigationSplitView: sidebar / liste / detay
- Sidebar: Bugün, Yaklaşan, Tümü, Tamamlanan + proje listesi (renk noktası + SF Symbol)
- Orta: seçili listeye göre görevler, @Query ile
- Sağ: seçili görevin detayı (başlık, notlar, proje, tarih, öncelik)
- Yeni görev: liste altındaki alandan Enter ile
- Silme: Delete tuşu + sağ tık menüsü
- .searchable ile arama
- Sidebar'a Liquid Glass (docs/06-LIQUID-GLASS.md kurallarına göre —
  içerik satırlarına cam UYGULAMA)

Erişilebilirlik: accessibilityReduceTransparency ve reduceMotion'ı
docs/06'daki gibi ele al.
```

---

## Faz 4 — Floating panel (EN ÖNEMLİ)

```
Faz 4'ü uygula: macOS floating panel.

docs/05-FLOATING-WIDGET.md'i baştan sona oku ve uygula — hover/expand,
kenara gizlenme (peek tutamağı) VE pinned (her zaman açık) modu dahil.
Oradaki kod örnekleri başlangıç noktası — genişlet ama davranışı değiştirme.

Oluşturulacaklar (Sources/macOS/Panel/):
- FloatingPanel.swift        — NSPanel alt sınıfı
- PanelGeometry.swift        — expandedFrame, snapToEdge: STATIC SAF FONKSİYONLAR
                               (test edilebilir olması için controller'dan ayrı)
- FloatingPanelController.swift — @MainActor @Observable, NSWindowDelegate,
                               isPinned state dahil
- EdgePeekState.swift        — kenara gizlenme / peek tutamağı state'i
- PanelRootView.swift        — hover algılama, collapsed/expanded geçiş
- CollapsedCapsuleView.swift — ~190x44, "N görev · Bugün"
- ExpandedPanelView.swift    — ~340x300, görev listesi + hızlı ekleme + pin butonu
- PeekHandleView.swift       — kenara yapışıkken görünen ince tutamak
- MenuBarController.swift    — MenuBarExtra (göster/gizle, pinle)

Mutlak kurallar:
1. Panelden tik atarken NSApp.activate() veya makeKeyAndOrderFront ÇAĞRILMAYACAK.
   Sadece orderFrontRegardless(). Odak kaybı kabul edilemez.
2. Genişleme yönü panelin ekrandaki konumuna göre; ekran dışına taşma yasak.
3. Pozisyon UserDefaults'a kaydedilecek, açılışta visibleFrame'e clamp edilecek.
4. Hover gecikmesi: girişte 120ms, çıkışta 400ms.
5. Kenara yapışınca 1.5 sn sonra peek tutamağına küçül, hover/tık ile geri gel.
6. isPinned true iken hover/gizlenme davranışları tamamen devre dışı kalır.
7. GlassDoKit.Task ile Swift'in kendi Task (concurrency) tipi çakışabilir —
   hover/gizlenme gecikmeleri için `_Concurrency.Task { ... }` kullan veya
   dosya başında açıkça ayrıştır.
8. NSApplication.didChangeScreenParametersNotification dinlenecek.

PanelGeometry için Tests/GlassDoKitTests'e testler yaz (docs/08-TESTING.md'de
örnek var): sağ kenar, alt kenar, ekran dışı clamp senaryoları.

Uygulamayı derleyip çalıştır, panelin göründüğünü doğrula.
```

### Faz 4 takılırsa — parçalara böl

```
Panel hover davranışında sorun var. Şu sırayla izole edelim:
1. Önce sadece SABİT boyutlu, hover'sız, sürüklenebilir bir panel çalıştır.
   Odak çalmadığını doğrula.
2. Sonra pozisyon kalıcılığını ekle.
3. Sonra hover ile genişlemeyi ekle.
4. En son peek tutamağı + pinned modu ekle.
Her adımda derleyip test et, hepsini birden deneme.
```

---

## Faz 5 — macOS Widget (WidgetKit)

```
Faz 5'i uygula: macOS WidgetKit widget'ı.

- project.yml'e GlassDoWidgets-macOS app-extension target'ı ekle,
  App Group'a (group.com.dadebay.glassdo) bağla, hem ana app hem widget
  target'ına entitlement ekle
- TodayWidget: bugünün görevleri, systemSmall / systemMedium
- TimelineProvider App Group'taki SwiftData store'dan okuyacak
  (AppStore.makeContainer artık groupContainer kullanmalı — bu fazda ekle)
- AppIntent ile widget içinden tik atma (interaktif widget)
- Ana app'te her yazma sonrası WidgetCenter.shared.reloadAllTimelines()
- Widget'ta Liquid Glass — containerBackground ile
- Boş durum: "Bugün için görev yok 🎉"

Widget'ı Notification Center'a veya masaüstüne ekleyip test et.
```

---

## Faz 6 — macOS cilası

```
Faz 6'yı uygula: macOS son dokunuşlar.

- KeyboardShortcuts paketiyle global kısayol (varsayılan ⌥Space)
- QuickAddWindow: Spotlight benzeri, ortada, Liquid Glass, Esc ile kapanır,
  Enter ile ekleyip kapanır
- SMAppService.mainApp.register/unregister — login item
- Ayarlar penceresi (Settings scene): Genel / Panel / Kısayollar sekmeleri
  · Panel opaklığı slider
  · Panel boyutu (küçük/orta/büyük)
  · Panelde hangi liste gösterilsin
  · Kenara gizlenme aç/kapa
  · Pinned mod varsayılanı
  · Login'de başlat toggle
- UNUserNotificationCenter ile bitiş tarihi bildirimleri
- İlk çalıştırma karşılama ekranı
```

---

## Faydalı ara promptlar

**Hata ayıklama:**
```
Panel hover'da açılmıyor. FloatingPanel'in acceptsMouseMovedEvents, style mask
ve NSHostingView bağlantısını kontrol et. docs/05-FLOATING-WIDGET.md'deki
"Bilinen tuzaklar" tablosunu gözden geçir ve hangisinin geçerli olduğunu söyle.
```

**Kod gözden geçirme:**
```
Sources/macOS/Panel/ altındaki tüm dosyaları docs/05-FLOATING-WIDGET.md'deki
şartnameyle karşılaştır. Uyuşmayan veya eksik olan davranışları listele.
```

**Widget veri paylaşımı sorunu:**
```
macOS widget boş görünüyor. Şu sırayla kontrol et:
1. App Group ID her iki target'ta da (ana app + widget) aynı mı
2. AppStore.makeContainer groupContainer kullanıyor mu
3. WidgetCenter.shared.reloadAllTimelines() her yazmadan sonra çağrılıyor mu
4. Widget'ın entitlement'ları doğru mu
Bulguları liste halinde ver, sonra düzelt.
```

**Tasarım denetimi:**
```
docs/06-LIQUID-GLASS.md'deki kurallara göre tüm view'ları denetle.
Özellikle: içerik satırlarına cam uygulanmış mı (uygulanmamalı),
iç içe cam var mı, reduceTransparency ele alınmış mı.
```
