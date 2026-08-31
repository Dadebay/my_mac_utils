# 006 — İşlemci sıcaklığı widget hiyerarşisini düzelt

- **Status**: TODO
- **Commit**: unborn (repository has no `HEAD` yet)
- **Severity**: HIGH
- **Category**: Purpose, cohesion & missed opportunity
- **Estimated scope**: 2 dosya, yaklaşık 70 satır

## Problem

Medium işlemci widget'ında grafik kalan bütün dikey alanı alıyor; ana değer olan
sıcaklık en alta, küçük bir yardımcı değer gibi yerleşiyor. Grafik ayrıca kendi
en yüksek örneğine normalize edildiği için 35–55 °C gibi dar bir seride bütün
çubuklar neredeyse tam yüksekliğe ulaşıyor. Kullanıcı trendi ve mevcut değeri
ilk bakışta ayırt edemiyor.

```swift
// Sources/Widgets/SystemWidgetViews.swift:355 — mevcut
} else {
    WidgetBarChart(
        samples: cpu.temperatureHistory.isEmpty ? cpu.history : cpu.temperatureHistory,
        color: tint,
        normalizesToPeak: true
    )
    .frame(maxHeight: .infinity)

    HStack(spacing: 8) {
        Spacer(minLength: 0)
        Text(temperatureText)
            .font(.system(size: 16, weight: .semibold))
        WidgetThermalBars(pressure: cpu.thermalPressure)
        Text(cpu.thermalPressure.label(s))
    }
}
```

```swift
// Sources/Widgets/WidgetChrome.swift:120 — mevcut
let peak = normalizesToPeak ? (samples.max() ?? 1) : 1
let fraction = peak > 0 ? min(max(sample / peak, 0), 1) : 0
```

WidgetKit zaman çizelgesi yenilemelerinde güvenilir ara kare üretmediği için
grafiğe sürekli veya giriş animasyonu eklemek bu sorunu çözmez.

## Target

Medium widget şu sırayla okunmalıdır:

1. Ortak `WidgetHeader`.
2. Sol tarafta 28 pt semibold, monospaced mevcut sıcaklık; sağda küçük termal
   durum etiketi.
3. Alt bölümde sabit 48 pt yüksekliğinde trend grafiği.

Sıcaklık grafiği 35...95 °C alanına sabitlenmelidir. Her örnek için:

```swift
fraction = clamp((temperature - 35) / 60, 0, 1)
```

Boş örnek 1.5 pt taban çizgisi olarak kalır. Renk mevcut eşiklerle korunur:
70 °C warning, 90 °C danger. Kart üzerinde sürekli animasyon, shimmer, pulse
veya her timeline yenilemesinde spring yoktur.

## Repo conventions to follow

- Ortak başlık `Sources/Widgets/WidgetChrome.swift:87` içindeki
  `WidgetHeader` ile çizilir.
- Renkler `WidgetPalette`; format `WidgetFormat.celsius`; termal durum
  `WidgetThermalBars` ve `ThermalPressure.label` üzerinden gelir.
- Sayısal değerlerde `.monospacedDigit()` kullanılmaya devam edilir.
- WidgetKit statik snapshot yaklaşımı korunur; repo yorumundaki “animasyon yok”
  kararı doğrudur.

## Steps

1. `Sources/Widgets/WidgetChrome.swift` içindeki `WidgetBarChart`'a yalnız bu
   kullanım için açık bir ölçek aralığı ekle: örneğin
   `var valueRange: ClosedRange<Double>?`. `valueRange` varsa fraction'ı
   `(sample - lowerBound) / (upperBound - lowerBound)` ile hesapla; yoksa
   mevcut `normalizesToPeak` davranışını aynen koru.
2. Aralık genişliği sıfırsa fraction'ı sıfır kabul et. Her sonucu 0...1'e
   clamp et; negatif height üretme.
3. `Sources/Widgets/SystemWidgetViews.swift` medium `ProcessorWidgetView`
   içindeki alt değer satırını grafiğin üstüne taşı. Sıcaklığı 28 pt semibold,
   durumu 11 pt secondary yap; ikisinin arasına `Spacer(minLength: 8)` koy.
4. Grafikte `normalizesToPeak: true` yerine `valueRange: 35...95` kullan ve
   `.frame(height: 48)` ver. Kalan alanı dolduran `.frame(maxHeight: .infinity)`
   kaldır.
5. Sensör yoksa `temperatureText == "—"` davranışını koru. Geçmiş boşsa CPU
   usage değerlerini derece gibi göstermeyi bırak; boş chart göster. Sıcaklık
   geçmişi mevcutsa yalnız onu çiz.
6. Small family yerleşimini ve Disk widget'ın `normalizesToPeak` davranışını
   değiştirme.

## Boundaries

- Widget'a timeline dışı timer, `TimelineView`, sonsuz animasyon veya yeni veri
  kaynağı ekleme.
- Disk ve ağ widget tasarımını değiştirme.
- Sıcaklık eşiklerini ve `SystemProvider` yenileme sıklığını değiştirme.
- Yeni bağımlılık ekleme.
- Dosyalar bu planla eşleşmiyorsa DUR ve kodu tahmin ederek yeniden yazma.

## Verification

- **Mechanical**:
  ```bash
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug -derivedDataPath /private/tmp/glassdo-widget-hierarchy build
  ```
- **Feel check**: medium Processor Temperature widget'ını 35, 48, 70, 90 ve
  95 °C fixture'larıyla önizle. Ana sıcaklık önce okunmalı; grafik 48 °C'de
  kartın tamamını doldurmamalı; 90 °C uyarı rengi göstermeli.
- Disk widget grafiğinin eski davranışını koruduğunu ayrıca doğrula.
- **Done when**: sıcaklık ana değer olarak üstte, trend sabit yükseklikte ve
  35...95 °C ölçeğinde; hiçbir öğe rounded rect dışına taşmıyor.

