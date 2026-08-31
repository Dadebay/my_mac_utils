# 02 — Mimari

## Target yapısı

```
GlassDo.xcodeproj
├── GlassDoKit          (Framework, macOS)  ← paylaşılan her şey
│   ├── Models/         SwiftData @Model tipleri
│   ├── Store/          ModelContainer kurulumu (yerel store)
│   ├── Services/       Notification, Hotkey protokolü, tarih yardımcıları
│   ├── DesignSystem/   Liquid Glass modifier'ları, renk/spacing token'ları
│   └── Intents/        App Intents (Siri, Shortcuts, interaktif widget)
│
├── GlassDo-macOS       (App)
│   ├── App/            @main, AppDelegate, MenuBarExtra
│   ├── Panel/          NSPanel + FloatingPanelController  ← kritik kısım
│   ├── MainWindow/     Sidebar + görev listesi + detay
│   └── QuickAdd/       ⌥Space ile açılan Spotlight-vari pencere
│
├── GlassDoWidgets-macOS (Widget Extension)
│   └── TodayWidget     Notification Center / masaüstü — bugünün görevleri
│
└── Tests/
    ├── GlassDoKitTests (Swift Testing)
    └── GlassDoUITests  (XCUITest)
```

> iOS uygulaması ve iOS widget'ları kapsam dışı (bkz. [00-OVERVIEW.md](00-OVERVIEW.md)).

## App Group

Widget extension'ın ana app ile aynı SwiftData store'u görmesi için **zorunlu**
(tek cihazda bile — widget ayrı bir sandbox process'i):

```
group.com.dadebay.glassdo
```

`ModelContainer` bu grubun container URL'inde kurulur. Widget ayrı bir process
olduğu için başka türlü veriye erişemez. Bu App Group **iCloud/CloudKit ile
karıştırılmamalı** — sadece yerel diskte ana app ile widget'ın aynı dosyayı
paylaşması için, sync amaçlı değil.

## Veri akışı

```
┌──────────────┐        ┌──────────────┐
│  macOS App   │        │ macOS Widget │
│  + Panel     │        │  (extension) │
└──────┬───────┘        └──────┬───────┘
       │                       │
       │  @Query / ModelContext│ read-only + AppIntent
       └───────────┬───────────┘
                   ▼
        ┌────────────────────────┐
        │  ModelContainer        │   App Group konteynerinde
        │  (SwiftData / SQLite)  │   default.store — tamamen yerel
        └────────────────────────┘
```

Yazma işleminden sonra widget'ı tazele:

```swift
WidgetCenter.shared.reloadAllTimelines()
```

## macOS pencere topolojisi

Üç ayrı pencere, üçü de farklı davranışta:

| Pencere | Tip | Level | Aktivasyon | Amaç |
|---|---|---|---|---|
| Ana pencere | `Window` (SwiftUI) | normal | evet | Tam liste yönetimi |
| Floating panel | `NSPanel` | `.floating` | **hayır** (nonactivating) | Her zaman görünen widget |
| Quick Add | `NSPanel` | `.floating` | evet (key olur) | ⌥Space ile hızlı ekleme |
| Menü bar | `MenuBarExtra` | — | — | Aç/kapa, ayarlar, çıkış |

`NSApplication.shared.setActivationPolicy(.regular)` kalır (Dock'ta ikon olsun).
İstersen ayarlardan `.accessory` yapıp Dock'tan gizleyebilirsin.

## Katman kuralları

- `GlassDoKit` **hiçbir** platform-özel API import etmez (`#if os()` ile ayrılmışlar hariç)
- View'lar SwiftData'ya `@Query` ile erişir, servis katmanı üzerinden değil
- `PanelController` bir `@Observable final class`, `@MainActor` işaretli
- Tüm SwiftData yazma işlemleri main actor'da (SwiftData henüz tam Sendable değil)
- Swift 6 strict concurrency **açık** — baştan açık olsun, sonradan düzeltmek acı

## project.yml

Gerçek `project.yml` proje kökünde — bu sadece güncel yapının özeti (macOS-only,
iOS/CloudKit kaldırıldı). Widget extension henüz eklenmedi (Faz 7'de eklenecek):

```yaml
name: GlassDo
options:
  bundleIdPrefix: com.dadebay
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    DEVELOPMENT_TEAM: "V793RH49BX"
    CODE_SIGN_STYLE: Automatic
    ENABLE_HARDENED_RUNTIME: YES

targets:
  GlassDoKit:
    type: framework
    platform: macOS
    sources: [Sources/GlassDoKit]
    info:
      path: Sources/GlassDoKit/Info.plist
      properties: {}

  GlassDo-macOS:
    type: application
    platform: macOS
    sources: [Sources/macOS]
    dependencies:
      - target: GlassDoKit
    info:
      path: Sources/macOS/Info.plist
      properties:
        LSUIElement: false
        NSHumanReadableCopyright: ""

  GlassDoKitTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/GlassDoKitTests]
    dependencies:
      - target: GlassDoKit
    info:
      path: Tests/GlassDoKitTests/Info.plist
      properties: {}
```

**Faz 7'de eklenecekler:** `KeyboardShortcuts` paketi (⌥Space için, Faz 8),
`GlassDoWidgets-macOS` app-extension target'ı (`NSExtensionPointIdentifier:
com.apple.widgetkit-extension`), App Group entitlement'ı her iki target'a.

> **Not (XcodeGen 2.46 tuzağı):** `info:` bloğu her target'ta **`path` alanı
> olmadan** kullanılırsa `xcodegen generate` "Decoding failed at path" hatasıyla
> parse edilemiyor; framework/test target'larında `info:` hiç yoksa da
> Info.plist üretilmiyor ve `codesign` "bundle format unrecognized" ile patlıyor.
> Her target'a (framework, app, test) mutlaka `info: path: .../Info.plist`
> ekle, `properties: {}` boş olsa bile.

Üretmek için:

```bash
xcodegen generate && open GlassDo.xcodeproj
```
