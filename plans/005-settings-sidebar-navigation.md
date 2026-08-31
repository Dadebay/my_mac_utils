# 005 — Settings sidebar gezinmesini doğrudan ve hafif yap

- **Status**: DONE
- **Commit**: unborn (repository has no `HEAD` yet)
- **Severity**: HIGH
- **Category**: Purpose & frequency, interruptibility, cohesion
- **Estimated scope**: 1 dosya, ~45 satır

## Problem

Settings sol menüsündeki her satır, `List` seçimiyle aynı alanda sıfır eşikli
bir drag gesture çalıştırıyor. Gesture mouse-down olayını yakalayıp macOS
`List` seçimiyle yarıştığı için Widgets açıkken General, Panel Size veya başka
bir bölüme tıklamak bazen hiçbir şey yapmıyor.

```swift
// Sources/macOS/Settings/SettingsView.swift:367-377 — current
.scaleEffect(!reduceMotion && isPressed ? 0.985 : 1)
.animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: isPressed)
.onHover { isHovering = $0 }
.simultaneousGesture(
    DragGesture(minimumDistance: 0)
        .onChanged { _ in isPressed = true }
        .onEnded { _ in isPressed = false }
)
```

Bölüm değişiminde tüm detail yüzeyi scale + spring ile yeniden kuruluyor. Bu,
günde onlarca kez kullanılan bir navigasyona gereksiz fiziksel hareket ekliyor
ve hızlı tıklamalarda geçişi ağır hissettiriyor.

```swift
// Sources/macOS/Settings/SettingsView.swift:412-424 — current
.transition(
    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
)
.animation(
    reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.30, dampingFraction: 1.0),
    value: selection
)
```

## Target

- Sidebar satırları yalnızca native `List(selection:)` ile seçilir; ek drag,
  tap veya zero-distance gesture bulunmaz.
- Tıklama anında sistemin kendi selection feedback'i gecikmeden görünür.
- Detail değişimi yalnızca `opacity` ile 160 ms güçlü ease-out kullanır;
  scale, slide ve bounce yoktur.
- Reduce Motion açıkken de yön hareketi yoktur; 120 ms opacity kalır.
- Kategori ikonları büyük iOS uygulama rozeti yerine sakin macOS sidebar
  sembolleri olur: tek tonlu tint, ince material zemin, seçiliyken beyaz sembol.

```swift
.transition(.opacity)
.animation(
    reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.16),
    value: selection
)
```

## Repo conventions to follow

- Selection kaynağı `List(selection: selectionBinding)` ve `.tag(category)`
  olarak kalır.
- SF Symbols ve semantic `primary/secondary` renkleri kullanılır.
- Yeni dependency veya özel gesture recognizer eklenmez.
- `accessibilityReduceMotion` korunur.

## Steps

1. `Sources/macOS/Settings/SettingsView.swift` içindeki
   `SettingsSidebarRowLabel` üzerinden `isPressed`, `scaleEffect` ve
   `DragGesture(minimumDistance: 0)` kodunu kaldır.
2. `rows(_:)` içinde satıra `isSelected: selection == category` geçir.
3. `SettingsCategoryIcon` gradient uygulama rozeti yerine tek tintli, ince
   stroke'lu sidebar ikonuna dönüştür; selected durumunda beyaz sembol kullan.
4. Detail transition'ı saf opacity yap; normalde 160 ms, Reduce Motion'da
   120 ms ease-out kullan.
5. Swift format, `git diff --check` ve unsigned Debug build çalıştır.

## Boundaries

- Ayar bölümlerinin içeriklerini değiştirme.
- Settings pencere kromuna veya masaüstü edge rail'e dokunma.
- Sidebar grup sırasını, aramayı ve kalıcı selection anahtarını değiştirme.
- Yeni dependency ekleme.

## Verification

- **Mechanical**:
  ```bash
  xcrun swift-format format --in-place Sources/macOS/Settings/SettingsView.swift
  git diff --check
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug \
    -derivedDataPath /private/tmp/glassdo-settings-sidebar-check \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
  ```
- **Feel check**: Widgets açıkken sırayla General → Panel Size → Rail Icons →
  Widgets → About tıkla. Her mouse-up tam bir kez seçim yapmalı; hızlı ve ters
  sıradaki tıklamalar engellenmemeli. İçerik yalnızca kısa crossfade yapmalı.
- **Done when**: hiçbir kategori tıklaması yutulmuyor, seçili satır anında
  değişiyor ve büyük gradient ikonlar sakin macOS sidebar ikonlarına dönüşüyor.
