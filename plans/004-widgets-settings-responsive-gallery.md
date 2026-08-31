# 004 — Widgets ayar galerisini responsive ve taşmasız yap

- **Status**: TODO
- **Commit**: unborn (repository has no `HEAD` yet)
- **Severity**: HIGH
- **Category**: Cohesion, layout & motion
- **Estimated scope**: 1 dosya, ~130 satır

## Problem

Widget önizlemeleri gerçek widget boyutlarında çizilip `scaleEffect(0.5)` ile
küçültülüyor. `scaleEffect` yalnızca çizimi değiştirir; SwiftUI layout ölçüsünü
değiştirmez. Üstelik aynı HStack içinde iki small ve bir medium tile toplanıyor.
Sonuç: önizlemeler ayar kartının dışına taşıyor, birbirlerinin üstünü kapatıyor
ve gradient canvas ile hiyerarşi okunmuyor.

```swift
// Sources/macOS/Settings/WidgetsSettingsSection.swift:79-90 — mevcut
    private var gallery: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                tile(size: .medium) { DiskWidgetView(...) }
                tile(size: .medium) { NetworkWidgetView(...) }
            }
            HStack(spacing: 12) {
                tile(size: .small) { BatteryWidgetView(...) }
                tile(size: .small) { MemoryWidgetView(...) }
                tile(size: .medium) { ProcessorWidgetView(...) }
            }
        }
```

```swift
// Sources/macOS/Settings/WidgetsSettingsSection.swift:121-144 — mevcut
        static let height: CGFloat = 155
        static let scale: CGFloat = 0.5
        ...
            .scaleEffect(TileSize.scale, anchor: .topLeading)
            .frame(
                width: size.width * TileSize.scale,
                height: TileSize.height * TileSize.scale
            )
```

Sabit `0.5` ölçek ayrıntı sütununun gerçek kullanılabilir genişliğini dikkate
almıyor. Pencere genişletildiğinde boşluk oluşuyor, daraltıldığında taşma oluyor.
Bu bir animation sorunu gibi görünse de kök neden layout ve clipping.

## Target

Widgets sayfası üç net katmandan oluşur:

1. Kısa kurulum açıklaması ve tek, belirgin “Widget'ları Düzenle” yardım satırı.
2. `Preview` başlıklı nötr bir canvas içinde bir featured System Overview
   önizlemesi.
3. `Individual Widgets` altında Disk, Network, Battery, Memory ve Processor
   önizlemelerinden oluşan responsive iki kolonlu grid.

Tüm önizlemeler:

- Kendi gerçek widget görünümünü kullanmaya devam eder; sahte kart çizilmez.
- Kullanılabilir genişlikten hesaplanan ölçekte render edilir.
- Layout frame ile visual frame birebir aynıdır.
- Kendi rounded rect sınırında clip edilir; hiçbir çizgi/yazı kart dışına çıkmaz.
- Dar genişlikte tek kolona düşer; minimum 760 pt Settings penceresinde yatay
  scroll gerektirmez.

Canvas nötr system surface kullanır (`primary.opacity(0.035)` veya material).
Mevcut doygun üç renkli wallpaper gradient kaldırılır; istenirse vurgu rengi
toplam opacity 0.10'u aşmayan çok hafif bir glow olarak kalabilir.

Resize sırasında animasyon YOKTUR: pencere imleci 1:1 takip eder. Eğer featured
widget seçilebilir yapılırsa sadece seçim değişimi 0.16 sn güçlü ease-out opacity
ve 0.98→1 scale kullanır; Reduce Motion'da yalnız opacity kalır. Canlı istatistik
örneklerinin her yenilenmesine animasyon bağlanmaz.

## Repo conventions to follow

- Gerçek widget view'larını kullanma kararı doğrudur ve korunur
  (`WidgetsSettingsSection.swift:5-9`).
- `SettingsCard` hiyerarşisini, `SystemStatsController` yaşam döngüsünü ve
  `SystemEntry` üretimini koru.
- UI giriş/çıkışları 300 ms altında kalmalı; burada 160 ms yeterli.
- Resize ve sürekli ölçüm high-frequency olaylarıdır; spring/timing animation
  ekleme.
- Hareket gerekiyorsa repo'nun güçlü ease-out eğrisini kullan:
  `.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)`.
- Reduced Motion'da konum/scale düşer, opacity geri bildirimi kalır.

## Steps

1. `Sources/macOS/Settings/WidgetsSettingsSection.swift` — mevcut iki sabit
   `HStack` ve doygun gradient'ten oluşan `gallery`yi kaldır. Yerine
   `GeometryReader` tabanlı, kullanılabilir genişliği okuyup kendi yüksekliğini
   deterministik hesaplayan bir preview canvas veya eşdeğer bir custom `Layout`
   kur. GeometryReader'a belirsiz/infinite height bırakma.

2. `TileSize.scale = 0.5` sabitini sil. `TileSize` gerçek widget ölçülerini
   (`small = 155×155`, `medium = 329×155`) tutmaya devam etsin. Her tile için:
   ```swift
   scale = min(1, availableWidth / nativeWidth)
   renderedHeight = nativeHeight * scale
   ```
   İç widget `nativeWidth × nativeHeight` çizilsin, top-leading anchor ile
   `scaleEffect(scale)` uygulansın ve dış wrapper tam olarak
   `availableWidth × renderedHeight` ölçüsünde olsun. Wrapper ayrıca
   `.contentShape` ve rounded-rect `.clipShape` kullansın. Böylece çizim ölçüsü
   ile layout ölçüsü ayrışmasın.

3. Gallery'nin üstüne featured `SystemOverviewWidgetView(entry: entry)` ekle.
   Kaynak view mevcutsa onu doğrudan kullan; yoksa yeni sahte overview çizmek
   yerine bu adımı atla ve Disk+Network'i featured iki kolon olarak tut. Bu
   planın scope'unu widget extension tasarımını değiştirecek şekilde genişletme.

4. Bireysel önizlemeleri `LazyVGrid` ile düzenle:
   `GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 12)`. Medium
   widget'lar kendi oranını korusun. Small Battery ve Memory tile'ları aynı grid
   hücresinde iki eşit alt sütun olarak gruplanabilir; 210 pt altına inerse alt
   alta düşsün. Bir satırda small+small+medium toplamını elle kurma.

5. Canvas dış padding 14 pt, tile aralığı 12 pt, canvas corner radius 18 pt,
   tile corner radius gerçek widget'ın 24 pt değerinin görsel ölçeğiyle uyumlu
   olsun. Canvas ve tüm alt önizlemelere clip uygula. `SettingsCard` dışına
   negatif offset veya overlay taşırma kullanma.

6. Başlık hiyerarşisini sadeleştir: kurulum metninin altında
   `Label("Preview", systemImage: "rectangle.grid.2x2")` 12 pt semibold;
   bireysel grid üstünde `Individual Widgets` 11 pt secondary/semibold kullan.
   Büyük all-caps başlık ekleme; mevcut SettingsCard başlığı zaten üst seviye.

7. “How they refresh” kartını koru fakat iki uzun hint'i maksimum okunabilir
   genişlikte bırak. Widget preview canvas ile üst üste binmediğini doğrula.

8. Sırf sayfa açıldığı için tile'lara stagger/entrance animasyonu ekleme.
   Featured seçim etkileşimi eklenirse state değişiminde:
   ```swift
   .transition(
       reduceMotion
           ? .opacity
           : .opacity.combined(with: .scale(scale: 0.98))
   )
   .animation(
       .timingCurve(0.23, 1, 0.32, 1, duration: 0.16),
       value: selectedPreview
   )
   ```
   Bunun için `@Environment(\.accessibilityReduceMotion)` ekle. Seçim yoksa bu
   state ve animasyonu hiç ekleme.

## Boundaries

- `Sources/Widgets` içindeki gerçek widget tasarımlarını bu plan kapsamında
  değiştirme.
- WidgetKit refresh cadence, controller start/stop veya veri modeline dokunma.
- Sabit bir ekran genişliğine göre magic-number scale yazma.
- `scaleEffect`i dış layout frame'i hesaplamadan tek başına kullanma.
- Grid/canvas için yatay `ScrollView` ekleme.
- Pencere resize'ına, GeometryReader width'ine veya canlı CPU/network sample'ına
  `.animation` bağlama.
- Aşırı doygun wallpaper, bloom, blur veya sürekli çalışan shimmer ekleme.
- Yeni paket/bağımlılık ekleme.
- `SystemOverviewWidgetView` mevcut değilse yeni bir widget ailesi icat etme;
  Disk+Network featured yerleşimine geri dön.
- Mevcut kod planla eşleşmiyorsa doğaçlama yapmadan DUR ve bildir.

## Verification

- **Mechanical**:
  ```bash
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug -derivedDataPath build/DerivedData build
  ```
- **Layout matrix**: Widgets ayarını 760×540, 880×660, 1200×800 ve maximized
  ölçülerde; Türkçe/English/Russian ve light/dark temalarda kontrol et.
  - Hiçbir tile SettingsCard veya preview canvas dışına taşmamalı.
  - Tile'lar birbirinin üstüne binmemeli.
  - Metin ve chart çizgileri kendi rounded rect'i içinde clip edilmeli.
  - Minimum genişlikte yatay scrollbar oluşmamalı.
  - Geniş pencerede preview gereksiz yere sol üstte küçücük kalmamalı.
- **Resize feel**: Pencere kenarını hızlı sürükle. Kartlar gecikmeden imleci
  takip etmeli; yaylanmamalı ve sonradan yerine oturmamalı.
- **Data check**: Controller güncellenirken yerleşim zıplamamalı. Sayfadan çıkıp
  dönünce sampling tek kez başlamalı ve kaybolunca durmalı.
- **Done when**: Kaynakta `TileSize.scale` kalmıyor; preview her test
  genişliğinde taşmasız, okunabilir ve gerçek widget view'larıyla eşleşiyor.

