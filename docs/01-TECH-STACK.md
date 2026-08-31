# 01 — Teknoloji Seçimi

> **Kapsam:** Proje macOS-only'e daraltıldı (iOS/iCloud kapsam dışı). Aşağıdaki
> karşılaştırma tablosu Swift/SwiftUI seçiminin genel gerekçesi olarak geçerli
> kalıyor, satırlardaki iOS/CloudKit referansları tarihsel/bilgilendirici.

## Karar: Swift 6 + SwiftUI (native)

Bu proje için başka bir seçenek pratikte yok. Sebepler aşağıda.

## Neden Swift/SwiftUI?

| Gereksinim | Swift/SwiftUI | Electron/Tauri | React Native | Flutter |
|---|---|---|---|---|
| Liquid Glass (native API) | ✅ birebir | ❌ taklit | ❌ taklit | ❌ taklit |
| `NSPanel` floating, nonactivating | ✅ | ⚠️ zor/hacky | ❌ | ❌ |
| iOS WidgetKit | ✅ | ❌ | ⚠️ köprü | ❌ |
| Control Center / Lock Screen | ✅ | ❌ | ❌ | ❌ |
| iCloud sync (SwiftData+CloudKit) | ✅ bedava | ❌ backend gerek | ❌ | ❌ |
| Uygulama boyutu | ~5 MB | ~120 MB | ~40 MB | ~30 MB |
| RAM (idle floating widget) | ~40 MB | ~250 MB | — | — |
| Menü bar / login item | ✅ | ⚠️ | ❌ | ❌ |
| App Store onayı | ✅ | ⚠️ | ✅ | ✅ |

Liquid Glass'ın gerçek refraksiyonu GPU üzerinde sistem tarafından çiziliyor.
Web tabanlı bir katmanda `backdrop-filter: blur()` ile taklit edilebilir ama
**aynı görünmez** — ışık kırılması, kenar parlaması ve morph animasyonu yok.

## Sürüm gereksinimleri

```
Swift             6.2+
Xcode             26.0+          (sende 26.6 ✅)
macOS deployment  26.0
iOS deployment    26.0
```

**Neden 26 minimum?** `.glassEffect()` ve `GlassEffectContainer` iOS 26 / macOS 26
API'leri. Daha eski OS desteklemek istersen `06-LIQUID-GLASS.md` içindeki
`AdaptiveGlass` fallback modifier'ı `.ultraThinMaterial` ile geri düşer — ama
v1'de buna girme, gereksiz karmaşıklık.

## Bağımlılıklar (Swift Package Manager)

Minimum tutuyoruz. Sadece iki tanesi gerçekten gerekli:

```swift
// Package dependencies
.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
// Global hotkey (⌥Space) için. Kendi başına yazmak CGEventTap + accessibility
// izni demek; bu paket Settings UI'ı da veriyor.

.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
// SADECE App Store dışı DMG dağıtımı yaparsan. App Store'a çıkacaksan ekleme.
```

**Kullanmayacaklarımız ve nedeni:**

- Realm / GRDB / Core Data elle → SwiftData zaten Core Data üstünde ve CloudKit'i bedava veriyor
- Alamofire → network yok
- Composable Architecture (TCA) → tek kullanıcılık app için aşırı ağır
- Firebase → iCloud varken gereksiz, ayrıca privacy manifest yükü getiriyor

## Mimari desen

**MV (Model–View)** + `@Observable` servisler. MVVM'in ViewModel katmanını
SwiftData `@Query` zaten karşılıyor; araya ViewModel koymak SwiftData'nın
otomatik güncellemesini bozar.

```
View  ──@Query──▶  SwiftData ModelContext  ──▶  CloudKit
  │
  └──@Environment──▶  Servisler (@Observable final class)
                       ├─ PanelController   (NSPanel yaşam döngüsü)
                       ├─ HotKeyService     (global kısayol)
                       ├─ NotificationService
                       └─ LaunchAtLoginService
```

## Proje dosyası yönetimi: XcodeGen

`.xcodeproj` binary bir dosya; bir agent'ın (Sonnet 5) onu düzenlemesi zor ve
merge conflict cehennemi. Bunun yerine:

```bash
brew install xcodegen
```

Proje bir `project.yml`'den üretilir. Sonnet 5 sadece `.swift` dosyaları ve
`project.yml` yazar, sonra `xcodegen generate` çalıştırır. Hazır `project.yml`
şablonu → [02-ARCHITECTURE.md](02-ARCHITECTURE.md#projectyml)

> Alternatif: Xcode'da elle "Multiplatform App" oluşturup target'ları manuel
> eklersin. Çalışır ama her yeni target'ta tıklama gerekir. XcodeGen'i öneriyorum.
