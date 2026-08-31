# 002 — Panel dışındaki hareketlere reduced-motion kapısı ekle

- **Status**: TODO
- **Commit**: (henüz commit yok — plan, commit'lenmemiş çalışma ağacına göre yazıldı)
- **Severity**: MEDIUM
- **Category**: Accessibility
- **Estimated scope**: 3 dosya, ~20 satır

## Problem

Kenar paneli (`EdgeRailView`, `EdgeShellView`, `EdgePanelController`) ve RAM
ekranı erişilebilirlik ayarındaki "hareketi azalt" tercihini doğru şekilde
karşılıyor. Ana pencere ve pencere değiştirici karşılamıyor — sistem ayarı
açıkken bile konum/ölçek değiştiren hareketler oynuyor.

Üç yer:

**a) Görev tamamlanınca patlayan parçacıklar.** Altı parçacık onay kutusundan
14 pt dışa fırlıyor. Tamamen dekoratif — hiçbir bilgi taşımıyor.

```swift
// Sources/macOS/MainWindow/TaskRow.swift:156-163 — mevcut
        .onChange(of: task.isCompleted) { _, isCompleted in
            guard isCompleted else { return }
            showCompletionBurst = true
            _Concurrency.Task { @MainActor in
                try? await _Concurrency.Task.sleep(for: .milliseconds(500))
                showCompletionBurst = false
            }
        }
```

```swift
// Sources/macOS/MainWindow/TaskRow.swift:172-173, 194-198 — mevcut
    private static let particleCount = 6
    private static let travelDistance: CGFloat = 14
    ...
    private func offset(for index: Int) -> CGSize {
        let angle = (Double(index) / Double(Self.particleCount)) * 2 * .pi
        let distance = expanded ? Self.travelDistance : 0
        return CGSize(width: cos(angle) * distance, height: sin(angle) * distance)
    }
```

**b) Kenar çubuğunun açılıp kapanması.** Sütunun tamamı kayarak giriyor/çıkıyor —
ekrandaki en büyük hareket.

```swift
// Sources/macOS/MainWindow/ContentView.swift:38-41 — mevcut
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            columnVisibility = sidebarHidden ? .all : .detailOnly
                        }
                    } label: {
```

**c) Pencere değiştirici kartlarının ölçeklenmesi.** Seçili/hover kart %4
büyüyor, hover kontrolleri 0.85 ölçekten geliyor. ⌥+Tab ile hızlı gezinirken
her Tab basışında tetikleniyor.

```swift
// Sources/macOS/WindowSwitcher/SwitcherOverlayView.swift:203-206 — mevcut
                    if isHovering {
                        windowControls
                            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .topLeading)))
                    }
```

```swift
// Sources/macOS/WindowSwitcher/SwitcherOverlayView.swift:221-222 — mevcut
            .scaleEffect(isHighlighted ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHighlighted)
```

## Target

"Hareketi azalt" açıkken konum ve ölçek değişimleri düşer; opaklık, renk ve
kenarlık geri bildirimi **AYNEN KALIR**. Hedef sıfır geri bildirim değil, daha
az ve daha yumuşak geri bildirim — kullanıcı hangi kartın seçili olduğunu ya da
bir görevin tamamlandığını hâlâ görebilmeli.

```swift
// hedef (a) — parçacık patlaması hiç başlamaz; tamamlanma zaten onay
// kutusunun dolu haliyle ve üstü çizili metinle belli oluyor
        .onChange(of: task.isCompleted) { _, isCompleted in
            guard isCompleted, !reduceMotion else { return }
            showCompletionBurst = true
            ...
        }
```

```swift
// hedef (b) — sütun anında yerine oturur
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                            columnVisibility = sidebarHidden ? .all : .detailOnly
                        }
```

```swift
// hedef (c) — ölçek düşer, mavi seçim kenarlığı (lineWidth 3) ve zemin
// opaklığı seçimi anlatmaya devam eder
            .scaleEffect(isHighlighted && !reduceMotion ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHighlighted)
```

```swift
// hedef (c) — hover kontrolleri ölçeksiz, yalnızca opaklıkla gelir
                    if isHovering {
                        windowControls
                            .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.85, anchor: .topLeading)))
                    }
```

## Repo conventions to follow

- Bu repo SwiftUI tarafında `@Environment(\.accessibilityReduceMotion)` kullanır
  ve değişkeni her zaman `reduceMotion` diye adlandırır.
- **Taklit edilecek örnek** — `Sources/macOS/Panel/EdgeRailView.swift:8` ve 35-43:
  ```swift
      @Environment(\.accessibilityReduceMotion) private var reduceMotion
      ...
      private var iconTransition: AnyTransition {
          reduceMotion
              ? .opacity
              : .opacity.combined(with: .scale(scale: 0.96))
      }
  ```
  Dikkat: azaltılmış modda animasyon tamamen silinmiyor, `.opacity` olarak
  korunuyor. Aynı yaklaşımı uygula.
- AppKit tarafında karşılığı `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
  (örnek: `Sources/macOS/Panel/EdgePanelController.swift:181`) — bu planda
  ihtiyaç yok, üç yer de SwiftUI.

## Steps

1. `Sources/macOS/MainWindow/TaskRow.swift` — `struct TaskRow` içinde, mevcut
   `@State private var isHovering = false` (satır 19) satırının hemen ÜSTÜNE
   ekle:
   ```swift
       @Environment(\.accessibilityReduceMotion) private var reduceMotion
   ```

2. `Sources/macOS/MainWindow/TaskRow.swift` — `checkbox` içindeki `.onChange`
   bloğunda (mevcut satır 157) `guard isCompleted else { return }` satırını
   şununla değiştir:
   ```swift
               // Parçacık patlaması tamamen dekoratif — hareketi azalt
               // açıkken hiç oynatma. Tamamlanma bilgisi onay kutusunun dolu
               // hali ve üstü çizili metinle zaten iletiliyor.
               guard isCompleted, !reduceMotion else { return }
   ```

3. `Sources/macOS/MainWindow/ContentView.swift` — `struct ContentView` içinde,
   mevcut `@AppStorage(AppTheme.storageKey)` satırının (satır 12) hemen ALTINA
   ekle:
   ```swift
       @Environment(\.accessibilityReduceMotion) private var reduceMotion
   ```

4. `Sources/macOS/MainWindow/ContentView.swift` — mevcut satır 39'daki
   `withAnimation(.easeInOut(duration: 0.22)) {` ifadesini şununla değiştir:
   ```swift
                           withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
   ```

5. `Sources/macOS/WindowSwitcher/SwitcherOverlayView.swift` — `private struct
   CardView: View` içinde, mevcut `@State private var isHovering = false`
   (satır 114) satırının hemen ÜSTÜNE ekle:
   ```swift
           @Environment(\.accessibilityReduceMotion) private var reduceMotion
   ```

6. `Sources/macOS/WindowSwitcher/SwitcherOverlayView.swift` — mevcut satır
   204-205'teki `windowControls` geçişini şununla değiştir:
   ```swift
                           windowControls
                               .transition(reduceMotion
                                   ? .opacity
                                   : .opacity.combined(with: .scale(scale: 0.85, anchor: .topLeading)))
   ```

7. `Sources/macOS/WindowSwitcher/SwitcherOverlayView.swift` — mevcut satır
   221'deki `.scaleEffect(isHighlighted ? 1.04 : 1.0)` ifadesini şununla
   değiştir:
   ```swift
               .scaleEffect(isHighlighted && !reduceMotion ? 1.04 : 1.0)
   ```
   Bir alttaki `.animation(.easeOut(duration: 0.12), value: isHighlighted)`
   satırı AYNEN KALIR — kenarlık ve zemin rengi geçişini hâlâ o sürüyor.

## Boundaries

- `.opacity`, renk, kenarlık (`strokeBorder`, `lineWidth`) ve
  `cardBorderColor` ile ilgili hiçbir şeyi kaldırma. Azaltılmış modda bunlar
  tek geri bildirim kaynağı olarak kalmalı.
- `CompletionBurst` struct'ının kendi iç animasyonuna (mevcut satır 187-191)
  dokunma — adım 2 zaten onu hiç oluşturmuyor.
- `SwitcherOverlayView` içindeki `thumbnailVisible` fade-in'ine (satır 180-186)
  dokunma: bu, asenkron yüklenen bir görüntünün ansızın belirmesini önlüyor,
  konum hareketi değil, ve zaten `WindowSwitcherSettings.fadeInPreviewEnabled`
  ile kullanıcı denetiminde.
- `EdgeRailView`, `EdgeShellView`, `EdgePanelController`, `RailPreview` ve
  `SystemMonitorView` dosyalarına dokunma — hepsi zaten doğru.
- Süre veya easing eğrisi değiştirme. Bu plan yalnızca erişilebilirlik kapısı
  ekler.
- Yeni bağımlılık ekleme.
- Adımlardaki kod bulduğun kodla eşleşmiyorsa DUR ve doğaçlama yapmadan bildir.

## Verification

- **Mechanical**: Proje kökünden şu komut hatasız `** BUILD SUCCEEDED **` vermeli:
  ```bash
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug -derivedDataPath build/DerivedData build
  ```
- **Feel check**: Sistem Ayarları → Erişilebilirlik → Ekran → **"Hareketi azalt"**
  açıkken uygulamayı yeniden başlat ve doğrula:
  - Ana pencerede bir görevi tamamla → yeşil parçacıklar **fırlamıyor**, ama
    onay kutusu doluyor ve metnin üstü çiziliyor.
  - Araç çubuğundaki kenar çubuğu düğmesine bas → sütun **kaymadan**, anında
    yerine oturuyor.
  - ⌥+Tab ile pencere değiştiriciyi aç, Tab ile gez → kartlar **büyümüyor**,
    ama seçili kartın mavi kenarlığı ve açık zemini net görünüyor.
  - Bir kartın üzerine gel → trafik ışığı düğmeleri **ölçeklenmeden**, yalnızca
    soluklaşarak geliyor.
  - Ayarı KAPAT, uygulamayı yeniden başlat → dört davranış da eski haline
    dönüyor.
- **Done when**: Şu komut üç dosyayı da listeliyor:
  ```bash
  grep -ln "accessibilityReduceMotion" Sources/macOS/MainWindow/TaskRow.swift Sources/macOS/MainWindow/ContentView.swift Sources/macOS/WindowSwitcher/SwitcherOverlayView.swift
  ```
