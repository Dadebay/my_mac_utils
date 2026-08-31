# 007 — Sistem özeti widget kartlarını eşit grid'e kilitle

- **Status**: TODO
- **Commit**: unborn (repository has no `HEAD` yet)
- **Severity**: HIGH
- **Category**: Cohesion, layout & performance
- **Estimated scope**: 1 dosya, yaklaşık 45 satır

## Problem

Sistem Özeti iki sütunun genişliğini hesaplıyor fakat üç satır için yükseklik
hesaplamıyor. Her `HStack` kendi içeriğinin ideal yüksekliğine göre ölçülüyor;
uzun içerikli Network/Battery satırı ile daha kısa kartlar farklı yüksekliğe
ulaşabiliyor ve son satır widget sınırında sıkışıp kırpılmış görünüyor.

```swift
// Sources/Widgets/SystemOverviewWidgetView.swift:14 — mevcut
let gap: CGFloat = 8
let columnWidth = (geometry.size.width - gap) / 2

VStack(spacing: gap) {
    HStack(spacing: gap) {
        networkCard.frame(width: columnWidth)
        batteryCard.frame(width: columnWidth)
    }
    HStack(spacing: gap) {
        diskCard.frame(width: columnWidth)
        processorCard.frame(width: columnWidth)
    }
    HStack(spacing: gap) {
        memoryCard.frame(width: columnWidth)
        systemCard.frame(width: columnWidth)
    }
}
```

Kart helper'ı `maxHeight: .infinity` istiyor, ancak üst satırlar kendilerine
deterministik bir satır yüksekliği vermediğinden bu istek tek başına eşitlik
garantilemiyor.

## Target

Large widget her zaman 2×3 düzen kullanmalı:

```swift
let gap: CGFloat = 8
let columnWidth = max((geometry.size.width - gap) / 2, 0)
let rowHeight = max((geometry.size.height - gap * 2) / 3, 0)
```

Altı kartın dış frame'i tam olarak `columnWidth × rowHeight` olmalıdır. Her
satır `rowHeight`, bütün grid `geometry.size` ölçüsünde kalmalı. İçerik kartın
dış ölçüsünü büyütememeli; uzun metinler `lineLimit(1)` ve mevcut
`minimumScaleFactor` ile içeride çözülmelidir.

Pencere/WidgetKit resize'ına animasyon eklenmez. Resize yüksek frekanslıdır ve
geometri imleci/sistem ölçüsünü 1:1 takip etmelidir.

## Repo conventions to follow

- Kart yüzeyi yalnız `overviewCard` helper'ında tanımlanır; ayrı kartlara farklı
  corner radius veya padding verilmez.
- `gap = 8`, kart padding'i `10`, corner radius `14` korunur.
- Semantik `Color.primary.opacity(...)` yüzeyleri ve `WidgetPalette` renkleri
  kullanılmaya devam eder.
- Processor grafiğinin 39 pt yüksekliği ve ring ölçüleri kart sınırı içinde
  kalıyorsa korunur.

## Steps

1. `Sources/Widgets/SystemOverviewWidgetView.swift` içindeki GeometryReader'da
   `rowHeight` hesapla: `(geometry.size.height - gap * 2) / 3`, alt sınır sıfır.
2. Her kart frame'ini `.frame(width: columnWidth, height: rowHeight)` yap.
   Yalnız genişlik veren altı çağrıyı değiştir.
3. Her `HStack`'e `.frame(width: geometry.size.width, height: rowHeight)` ver;
   `VStack`'i `.frame(width: geometry.size.width, height: geometry.size.height,
   alignment: .topLeading)` ile sınırla.
4. Altı kartta tek satıra sığmayabilecek text alanlarını kontrol et. Eksik
   olanlara yalnız `.lineLimit(1)` ve gerekirse `.minimumScaleFactor(0.65)` ekle;
   fontları veya kart padding'ini kart bazında küçültme.
5. `overviewCard` sonunda aynı 14 pt rounded rect ile `.clipShape(...)` ekle;
   grafik, chip veya uzun lokalizasyon kart dışına çizilemesin.
6. Rusça, Türkçe ve İngilizce metinleri aynı fixture ile dene. Bir dil için
   ayrı frame değeri veya sabit offset ekleme.

## Boundaries

- Large widget'ın 2×3 bilgi mimarisini değiştirme.
- Kartları ScrollView içine alma; widget içinde scrolling yoktur.
- `SystemSnapshot`, provider, refresh cadence veya individual widget'lara
  dokunma.
- Width/height değişimine `.animation` bağlama; keyframe/spring ekleme.
- Yeni bağımlılık ekleme.
- Dosya planla eşleşmiyorsa DUR ve raporla.

## Verification

- **Mechanical**:
  ```bash
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug -derivedDataPath /private/tmp/glassdo-overview-grid build
  ```
- **Geometry check**: Debug overlay ile altı kartın width ve height değerlerini
  ölç; aynı sütundaki ve farklı satırlardaki değerler eşit olmalı.
- **Feel check**: desktop large widget'ı light/dark ve Türkçe/English/Russian
  dillerinde aç. Alt System/Memory satırı alt köşede kırpılmamalı; bütün gap'ler
  8 pt görünmeli. Widget yeniden boyutlanırken gecikme veya yaylanma olmamalı.
- **Done when**: altı kartın dış ölçüsü birebir eşit, dışarı taşma yok ve son
  satır tamamen görünür.

