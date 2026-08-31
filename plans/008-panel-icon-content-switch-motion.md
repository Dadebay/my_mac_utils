# 008 — Açık panelde ikonlar arası geçişi izole et

- **Status**: TODO
- **Commit**: unborn (repository has no `HEAD` yet)
- **Severity**: HIGH
- **Category**: Purpose, interruptibility, cohesion & performance
- **Estimated scope**: 3 dosya, yaklaşık 70 satır

## Problem

Aynı rail ikonuna basıldığında panel rail ↔ expanded arasında geçiyor ve AppKit
pencere frame animasyonu düzgün çalışıyor. Panel zaten açıkken başka bir ikona
basıldığında ise yalnız `content` değişiyor; `visualState` zaten `.expanded`
olduğu için panel açılış transition'ı yeniden çalışmıyor.

```swift
// Sources/macOS/Panel/EdgePanelController.swift:184 — mevcut
func selectContent(_ newContent: PanelContent) {
    if content == newContent && visualState == .expanded {
        setExpanded(false)
    } else {
        content = newContent
        setExpanded(true)
        if let feature = newContent.usageFeature {
            UsageStore.track(feature, source: .edgeRail)
        }
    }
}
```

`setExpanded(true)` açık panelde no-op olur:

```swift
// Sources/macOS/Panel/EdgePanelController.swift:217 — mevcut
guard newState != visualState else { return }
```

SwiftUI kabuğunda transition yalnız expanded içeriğin eklenme/kaldırılmasına
bağlıdır; `controller.content` değişimine bağlı ayrı bir host/transition yoktur:

```swift
// Sources/macOS/Panel/EdgeShellView.swift:68 — mevcut
if controller.visualState == .expanded {
    panelContent.transition(contentTransition)
}
```

Ayrıca seçim animasyonu rail'in tamamına uygulanıyor:

```swift
// Sources/macOS/Panel/EdgeRailView.swift:148 — mevcut
.animation(iconAnimation, value: iconVisibility)
.animation(selectionAnimation, value: controller.content)
.animation(selectionAnimation, value: controller.mode)
```

Bu global transaction yalnız beyaz selection highlight'ını değil, aynı VStack
altındaki ikon foreground, hover ve diğer animatable özellikleri de content
değişimi transaction'ına sokabilir. Sonuç: ikonlar arası geçişte ray ve içerik
birbirinden kopuk, zıplayan/bozulan bir hareket gibi görünür.

## Target

İki motion yolu bilinçli olarak farklı ama aynı fiziksel dile sahip olmalıdır:

1. **Aynı ikona tekrar basma:** mevcut panel frame aç/kapat davranışı aynen
   korunur. `EdgePanelController.setVisualState` içindeki drawer eğrisi
   `CAMediaTimingFunction(0.32, 0.72, 0, 1)` ve mevcut süreler değişmez.
2. **Açık panelde farklı ikona basma:** pencerenin width/height/frame'i hiç
   animasyon görmez. Rail sabit kalır. Yalnız içerik slotu eski sayfayı 120 ms
   güçlü ease-out ile çıkarır ve yeni sayfayı 180 ms güçlü ease-out ile getirir.
3. Selection highlight mevcut `Motion.railSelection` spring'iyle ikonlar arasında
   hareket eder; ikon satırlarının position/scale/size değerleri animasyona
   girmez.
4. Hızlı art arda ikon tıklamalarında geçiş mevcut görsel durumdan yeniden hedef
   alır; panel önceki animasyonun bitmesini beklemez ve kuyruk oluşturmaz.
5. Reduce Motion açıkken konum/scale hareketi yoktur; yalnız 100 ms opacity
   geri bildirimi kalır.

Güçlü ease-out değeri repo convention'ı ile aynıdır:

```swift
.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
```

İçerik geçişinde slide, bounce veya scale kullanma. Farklı sayfalar aynı panel
slotunu işgal eder; kısa opacity geçişi doğru spatial modeldir.

## Repo conventions to follow

- `Sources/GlassDoKit/DesignSystem/Tokens.swift:15-21` içindeki motion token'ları
  tek kaynak olarak kullanılır.
- Panel aç/kapat frame animasyonu
  `Sources/macOS/Panel/EdgePanelController.swift:247-259` içindeki AppKit drawer
  eğrisidir; doğru çalışıyor ve değiştirilmemelidir.
- Rail'in panel frame hareketinden ayrılması için
  `EdgeShellView.swift:90-100` içindeki `.animation(nil, value:
  controller.visualState)` kararı korunur.
- `RailIconButton` seçim yüzeyi için mevcut `matchedGeometryEffect` korunur.
- `accessibilityReduceMotion` hareketi azaltırken opacity geri bildirimini
  korur.

## Steps

1. `Sources/GlassDoKit/DesignSystem/Tokens.swift` içine iki açık token ekle:

   ```swift
   public static let panelContentSwapIn = Animation
       .timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
   public static let panelContentSwapOut = Animation
       .timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
   ```

   Var olan panel visibility token'larını yeniden adlandırma veya silme.

2. `Sources/macOS/Panel/EdgeShellView.swift` içinde panelin açılıp kapanmasını
   yöneten dış transition ile açık panelde sayfa değişimini yöneten iç
   transition'ı ayır. Mevcut `contentTransition` yalnız dış visibility için
   kalsın.

3. Kalıcı bir `panelContentHost` oluştur. Host expanded kaldığı sürece view
   ağacında kalmalı; içindeki sayfa `controller.content` ile kimliklenmelidir:

   ```swift
   private var panelContentHost: some View {
       ZStack(alignment: .topLeading) {
           panelContent
               .id(controller.content)
               .transition(contentSwapTransition)
       }
       .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
       .clipped()
       .animation(contentSwapAnimation, value: controller.content)
   }
   ```

   Leading ve trailing edge dallarında `panelContent` yerine bu host'u kullan.
   Dışarıda `.transition(contentTransition)` host'a uygulanmalıdır.

4. Swap transition'ı şu şekilde tanımla:

   ```swift
   private var contentSwapTransition: AnyTransition {
       .asymmetric(
           insertion: .opacity.animation(
               reduceMotion
                   ? .easeOut(duration: 0.10)
                   : Motion.panelContentSwapIn
           ),
           removal: .opacity.animation(
               reduceMotion
                   ? .easeOut(duration: 0.10)
                   : Motion.panelContentSwapOut
           )
       )
   }
   ```

   `contentSwapAnimation` aynı insertion token'ını kullanabilir. Eğer transition
   içindeki explicit animation ile container `.animation` çift animasyon
   oluşturuyorsa yalnız transition animation'larını bırak; iki farklı animation
   modifier'ı aynı property'ye uygulama.

5. `PanelTaskListView(showCompleted: false)` ile
   `PanelTaskListView(showCompleted: true)` aynı concrete view type olduğu için
   `.id(controller.content)` zorunludur. Bu kimliği kaldırma; Tasks ↔ Completed
   geçişindeki eski state/content karışmasını önler.

6. `Sources/macOS/Panel/EdgeRailView.swift` sonundaki şu iki global modifier'ı
   kaldır:

   ```swift
   .animation(selectionAnimation, value: controller.content)
   .animation(selectionAnimation, value: controller.mode)
   ```

   `iconVisibility` animation'ı kalmalıdır; o yalnız Settings'ten ikon görünürlük
   listesi değiştiğinde çalışır.

7. Selection animation'ını `Sources/macOS/Panel/RailIconButton.swift` içinde
   highlight'ın sahibi olan en dar katmana taşı. `isActive` değişimine bağla:

   ```swift
   private var selectionAnimation: Animation {
       reduceMotion ? .easeOut(duration: 0.10) : Motion.railSelection
   }
   ```

   `selectionBackground` veya onu taşıyan ZStack üzerinde
   `.animation(selectionAnimation, value: isActive)` kullan. Tüm rail VStack'i,
   ikon row frame'lerini veya badge offset'lerini bu animation'a dahil etme.
   `matchedGeometryEffect(id:selectionID:namespace:)` korunmalıdır.

8. Eğer local `.animation(... value: isActive)` matched geometry hareketini
   tetiklemiyorsa Button action içinde yalnız content değişimini
   `withAnimation(selectionAnimation)` transaction'ına al. Bu fallback'te
   panel AppKit frame değişimini SwiftUI transaction'ına bağlama; önce farklı
   content ile aynı-content toggle yollarını ayır. En dar local modifier çalışan
   çözümse fallback'i ekleme.

## Boundaries

- `EdgePanelController.setVisualState` süre/easing/frame hesabını değiştirme.
- İkon değişiminde paneli önce kapatıp sonra yeniden açma. Bu 2× motion üretir,
  yavaş ve kesintiye uğramayan bir sıra oluşturur.
- Window width, height, panel frame, padding, rail position veya icon row height
  animasyonu ekleme.
- İçerik değişimine spring/bounce/slide/scale bağlama.
- Rail'i `.id(controller.content)` ile yeniden yaratma; yalnız içerik sayfasına
  identity ver.
- Scroll pozisyonlarını bütün sayfalar arasında ortaklaştırmaya çalışma.
- Hover, drag, pin, sliver ve liquid bubble davranışlarına dokunma.
- `drawingGroup()` rozet workaround'unu kaldırma.
- Yeni dependency ekleme.
- Kaynak planla eşleşmiyorsa DUR ve doğaçlama geniş refactor yapma.

## Verification

- **Mechanical**:

  ```bash
  git diff --check
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS \
    -configuration Debug \
    -derivedDataPath /private/tmp/glassdo-panel-content-swap \
    -allowProvisioningUpdates build
  ```

- **Feel check — trailing edge**:
  1. Tasks ikonuyla paneli aç: mevcut drawer animasyonu değişmemeli.
  2. Açıkken Completed → Folders → Memory → Network ikonlarına bas.
  3. Pencere kenarı ve rail tek piksel bile hareket etmemeli.
  4. Beyaz selection highlight ikonlar arasında tek parça hareket etmeli;
     ikonların kendisi zıplamamalı veya büyüyüp küçülmemeli.
  5. Eski içerik 120 ms içinde kaybolmalı, yeni içerik 180 ms içinde görünmeli;
     boş siyah frame veya iki sayfanın uzun süre üst üste görünmesi olmamalı.

- **Interruptibility**: Tasks/Completed/Folders ikonlarına saniyede 5-6 kez
  art arda bas. Son tıklanan sayfa hemen hedef olmalı; animasyon kuyruğu, eski
  sayfaya geri sıçrama veya donmuş highlight olmamalı.
- **Toggle regression**: aktif ikona tekrar basınca panel kapanmalı; tekrar
  basınca aynı mevcut drawer animasyonuyla açılmalı.
- **Leading edge**: paneli sol kenara taşı ve aynı kontrolleri tekrarla.
- **Reduced Motion**: System Settings'ten Reduce Motion aç. İçerik yalnız kısa
  opacity ile değişmeli; selection highlight teleport/fade edebilir ama hareketli
  spring olmamalı.
- **Hit testing**: hızlı içerik geçişi sırasında her rail ikonu tıklanabilir
  kalmalı; panel content rail'in üstüne çıkmamalı.
- **Done when**: aynı ikon toggle motion'ı korunuyor; farklı ikon geçişinde
  yalnız içerik ve selection highlight animasyon görüyor; rail/panel geometrisi
  sabit ve hızlı tıklamalar kesintisiz çalışıyor.

