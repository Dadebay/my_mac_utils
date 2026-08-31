# 05 — Floating Widget (macOS)

Projenin kalbi. İstenen davranış:

1. Ekranda küçük bir cam kapsül duruyor, her uygulamanın üstünde
2. İstediğin yere **sürüklüyorsun**, pozisyonu hatırlanıyor
3. Üzerine gelince (hover) **genişleyip** görevleri gösteriyor
4. Fare ayrılınca geri küçülüyor
5. Panelde tik atınca **odaktaki uygulama değişmiyor** (kod yazarken Xcode odakta kalıyor)
6. Ekran kenarına sürükleyince yapışıyor, isteğe bağlı olarak kenara gizleniyor

## iOS Kısıtı (önce bunu bil)

iOS'ta bu **yapılamaz.** Apple, üçüncü parti uygulamaların diğer uygulamaların
üzerinde çizmesine izin vermiyor — Android'deki `SYSTEM_ALERT_WINDOW` izninin
karşılığı yok, jailbreak dışında yolu yok, App Store'a da girmez.

iOS'taki karşılıkları:

| İstenen | iOS karşılığı |
|---|---|
| Ekranda duran küçük kart | Home Screen widget (small) |
| Kilit ekranında görmek | Lock Screen widget |
| Her yerden hızlı erişim | Control Center kontrolü / Action Button |
| Aktif görev göstergesi | Live Activity + Dynamic Island |
| Hover'da açılma | Widget'a dokun → app açılır (hover kavramı yok) |

Yani: **serbest sürüklenen panel = sadece macOS.** iOS tarafı widget'larla çözülüyor.

---

## Teknik yaklaşım

### Pencere tipi: `NSPanel`

`NSWindow` değil `NSPanel`, çünkü panel `.nonactivatingPanel` style mask'ini
destekliyor — tıklandığında uygulamayı öne getirmiyor.

```swift
// GlassDo-macOS/Panel/FloatingPanel.swift
import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // --- Görünüm ---
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false            // gölgeyi SwiftUI tarafında çiziyoruz
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // --- Davranış ---
        level = .floating            // normal pencerelerin üstünde
        isFloatingPanel = true
        hidesOnDeactivate = false    // app arkaya geçse de görünür kal
        isMovableByWindowBackground = true   // her yerinden sürüklenebilir
        acceptsMouseMovedEvents = true       // hover için ŞART
        isReleasedWhenClosed = false

        // Tüm Space'lerde + full-screen uygulamaların üstünde
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle           // ⌘` döngüsüne girmesin
        ]

        // Mission Control / ekran görüntüsü davranışı
        animationBehavior = .utilityWindow
    }

    // Borderless pencere normalde key olamaz; metin girişi için gerekli
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

> **Level seçimi:** `.floating` çoğu durumda yeterli. Menü barın ve
> Mission Control'ün de üstünde olsun istersen `.statusBar` veya
> `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))`
> kullan — ama bu, uyarı diyaloglarını da örter, önerilmez.

### Odak çalmama (en kritik nokta)

Üç şey birlikte gerekli:

```swift
// 1. styleMask'te .nonactivatingPanel  ✓ (yukarıda)

// 2. Uygulama policy'si — panel görünürken app'i öne getirme
// Panel içindeki butonlar NSApp.activate() ÇAĞIRMAMALI

// 3. Panel'i gösterirken:
panel.orderFrontRegardless()   // makeKeyAndOrderFront DEĞİL
```

`makeKeyAndOrderFront(_:)` uygulamayı aktive eder → Xcode'dan odak kaçar. Asla kullanma.
Sadece panelde metin girişi gerektiğinde (quick add alanı) geçici olarak
`panel.makeKey()` çağır, alandan çıkınca `panel.resignKey()`.

### Sürükleme + pozisyon kalıcılığı

`isMovableByWindowBackground = true` bedava sürükleme veriyor. Pozisyonu kaydet:

```swift
// FloatingPanelController.swift
@MainActor @Observable
final class FloatingPanelController: NSObject, NSWindowDelegate {

    private var panel: FloatingPanel?
    private(set) var isExpanded = false

    static let collapsedSize = CGSize(width: 190, height: 44)
    static let expandedSize  = CGSize(width: 340, height: 300)

    // Sürükleme bitince kaydet
    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        snapToEdgeIfNeeded(panel)
        UserDefaults.standard.set(
            NSStringFromPoint(panel.frame.origin),
            forKey: "panel.origin"
        )
    }

    private func restoreOrigin(for panel: FloatingPanel) {
        guard let raw = UserDefaults.standard.string(forKey: "panel.origin"),
              let screen = NSScreen.main else {
            positionTopRight(panel); return
        }
        var origin = NSPointFromString(raw)
        // Ekran değişmiş/çözünürlük düşmüş olabilir → görünür alana zorla
        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)
    }
}
```

**Dikkat:** Panel genişlediğinde sağ kenardaysa ekran dışına taşar. Genişleme
yönünü panelin ekrandaki konumuna göre seç:

```swift
// Panel ekranın sağ yarısındaysa sola doğru genişlet
private func expandedFrame(from collapsed: NSRect, on screen: NSScreen) -> NSRect {
    let s = Self.expandedSize
    let onRightHalf = collapsed.midX > screen.visibleFrame.midX
    let x = onRightHalf ? collapsed.maxX - s.width : collapsed.minX
    // Yukarıdan aşağı açılsın: üst kenarı sabit tut (macOS'ta y aşağıdan ölçülür)
    let y = collapsed.maxY - s.height
    var f = NSRect(x: x, y: y, width: s.width, height: s.height)

    // Ekran dışına taşmayı engelle
    let v = screen.visibleFrame
    f.origin.x = min(max(f.minX, v.minX + 8), v.maxX - s.width - 8)
    f.origin.y = min(max(f.minY, v.minY + 8), v.maxY - s.height - 8)
    return f
}
```

### Hover ile genişleme

İki uygulanabilir yaklaşım var. **A'yı öner, B'yi yedek tut.**

#### Yaklaşım A — Pencere frame'ini animasyonla değiştir (önerilen)

```swift
func setExpanded(_ expand: Bool) {
    guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
    guard expand != isExpanded else { return }
    isExpanded = expand

    let target = expand
        ? expandedFrame(from: collapsedFrame, on: screen)
        : collapsedFrame

    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.28
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().setFrame(target, display: true)
    }
}
```

SwiftUI tarafında hover algılama + gecikme (titremeyi önler):

```swift
struct PanelRootView: View {
    @Environment(FloatingPanelController.self) private var controller
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Group {
            if controller.isExpanded { ExpandedPanelView() }
            else { CollapsedCapsuleView() }
        }
        .onHover { inside in
            hoverTask?.cancel()
            hoverTask = Task {
                // girişte 120ms, çıkışta 400ms bekle → yanlışlıkla açılmasın/kapanmasın
                try? await Task.sleep(for: .milliseconds(inside ? 120 : 400))
                guard !Task.isCancelled else { return }
                controller.setExpanded(inside)
            }
        }
    }
}
```

> **Bilinen tuzak:** Pencere küçülürken fare hâlâ eski büyük alanın içindeyse
> `onHover(false)` tetiklenmeyebilir. Çözüm: `NSTrackingArea`'yı
> `.activeAlways` + `.mouseEnteredAndExited` + `.inVisibleRect` ile content
> view'a elle ekle, ya da 400 ms'lik çıkış gecikmesini koru.

#### Yaklaşım B — Sabit büyük pencere, şeffaf boşluk

Pencere her zaman `expandedSize` kadar; collapsed halde içerik küçük çiziliyor,
etrafı şeffaf. Animasyon tamamen SwiftUI'da → **çok daha akıcı.**
Bedeli: şeffaf alan altındaki tıklamaları yutar. Çözüm:

```swift
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // Sadece opak içerik üzerindeyse olayı al
        return hit === self ? nil : hit
    }
}
```
SwiftUI'ın hosting view'ı bunu her zaman doğru raporlamaz. Riskli; A çalışmazsa dene.

### Kenara yapışma (snap) ve gizlenme

```swift
private func snapToEdgeIfNeeded(_ panel: FloatingPanel) {
    guard let v = panel.screen?.visibleFrame else { return }
    let threshold: CGFloat = 24
    var f = panel.frame
    if abs(f.minX - v.minX) < threshold { f.origin.x = v.minX + 8 }
    if abs(f.maxX - v.maxX) < threshold { f.origin.x = v.maxX - f.width - 8 }
    if abs(f.maxY - v.maxY) < threshold { f.origin.y = v.maxY - f.height - 8 }
    if abs(f.minY - v.minY) < threshold { f.origin.y = v.minY + 8 }
    panel.setFrame(f, display: true, animate: true)
}
```

**Kenara gizlenme (v1) — "peek" tutamağı:** Android/Samsung Edge Panel'deki gibi
davranış (referans: kullanıcının gönderdiği ekran görüntüsü). Panel kenara
yapıştıktan birkaç saniye sonra kendini kenara doğru kaydırır, sadece
6–10 pt'lik yuvarlatılmış bir tutamak (handle) görünür kalır — geri kalanı
ekran dışında. Detaylar:

- Gizlenme gecikmesi: kenara yapıştıktan **1.5 sn** sonra otomatik gizlen
  (kullanıcı hâlâ etkileşimdeyse gizlenme).
- Tutamak, panelin hangi kenara yapıştığına göre o kenarda ince bir kapsül
  olarak kalır (`glassEffect(.regular, in: .capsule)`), üstünde küçük bir
  ok/chevron ikonu.
- Tutamağa hover → panel **tam boy** geri kayar (snap-back), tekrar hover
  dışına çıkınca (ve pinned değilse) gizlenme döngüsü baştan başlar.
- Tutamağa tıklama da aynı şekilde geri getirir (trackpad'siz kullanım için).
- Gizliyken de `orderFrontRegardless()` ile en üstte kalmaya devam eder;
  odak asla çalınmaz.
- Ayarlardan aç/kapa: "Kenara gizlenme" toggle'ı (bkz. Faz 8, Ayarlar).

```swift
enum PanelEdge { case left, right, top, bottom, none }

@Observable
final class EdgePeekState {
    var isPeeking = false        // true = sadece tutamak görünüyor
    var attachedEdge: PanelEdge = .none
    private var hideTask: Task<Void, Never>?

    func scheduleAutoHide(after delay: Duration = .seconds(1.5)) {
        hideTask?.cancel()
        guard attachedEdge != .none else { return }
        hideTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.collapse) { isPeeking = true }
        }
    }

    func reveal() {
        hideTask?.cancel()
        withAnimation(Motion.expand) { isPeeking = false }
    }
}
```

### Her zaman açık kal (Pinned) modu

İsteğe bağlı ikinci mod: panel **hiç küçülmeden**, her zaman `expandedSize`
boyutunda ve genişlemiş görünümde ekranda sabit dursun — hover'ı, otomatik
gizlenmeyi ve tutamak davranışını devre dışı bırakır. Menü bar ve panel
başlığındaki bir pin (📌) butonuyla açılıp kapatılır.

- `FloatingPanelController` içinde `isPinned: Bool` (UserDefaults'a kalıcı).
- `isPinned == true` iken:
  - `setExpanded(_:)` hover'dan tetiklenmez, panel her zaman expanded kalır
  - `EdgePeekState.scheduleAutoHide` çağrılmaz — kenara yapışsa bile gizlenmez
  - Panel başlığında pin ikonu dolu (📌 vs 📍) gösterilir
- `isPinned == false` iken normal hover + kenara gizlenme davranışına döner.
- Varsayılan: `isPinned = false` (mevcut hover davranışı).

```swift
extension FloatingPanelController {
    func togglePinned() {
        isPinned.toggle()
        UserDefaults.standard.set(isPinned, forKey: "panel.isPinned")
        if isPinned {
            edgePeek.reveal()          // pinlenince tutamak modundan çık
            setExpanded(true)          // ve genişlemiş halde sabitle
        }
    }
}
```

> Not: Pinned modda panel yine `.nonactivatingPanel` kalır — odak kuralı
> (NSApp.activate() / makeKeyAndOrderFront çağrılmaz) burada da geçerli.

### Panelin içeriği

```swift
struct ExpandedPanelView: View {
    @Query(filter: Task.todayPredicate(),
           sort: \Task.sortIndex) private var tasks: [Task]
    @Environment(\.modelContext) private var context
    @Namespace private var glassNS

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider().opacity(0.25)
                ForEach(tasks.prefix(6)) { task in
                    TaskRow(task: task) { toggle(task) }
                }
                if tasks.isEmpty { emptyState }
                quickAddField
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .glassEffectID("panel", in: glassNS)
        }
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }

    private func toggle(_ task: Task) {
        withAnimation(.snappy) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? .now : nil
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        // NSApp.activate() ÇAĞIRMA — odak kaçar
    }
}
```

## Yapılacaklar kontrol listesi

- [ ] `FloatingPanel: NSPanel` — style mask, level, collection behavior
- [ ] `FloatingPanelController` — göster/gizle, expand/collapse, pozisyon kaydet
- [ ] `NSHostingView` ile SwiftUI içeriği bağla, `.environment(controller)` geçir
- [ ] Hover gecikmeli genişleme (in 120ms / out 400ms)
- [ ] Genişleme yönü ekran konumuna göre
- [ ] Ekran dışına taşma koruması (`visibleFrame` clamp)
- [ ] Kenar snap
- [ ] Kenara gizlenme: 1.5 sn sonra tutamağa küçülme, hover/tık ile geri gelme
- [ ] Pinned (her zaman açık) modu: pin butonu, hover/gizlenme devre dışı kalıyor
- [ ] Çoklu monitör: `NSScreen.screens` değişince pozisyonu doğrula
  (`NSApplication.didChangeScreenParametersNotification`)
- [ ] Menü bar → "Widget'ı Göster/Gizle", "Paneli Pinle"
- [ ] Ayarlar: opaklık, boyut, hangi liste gösterilsin, kenara gizlenme aç/kapa

## Bilinen tuzaklar

| Sorun | Sebep | Çözüm |
|---|---|---|
| Panele tıklayınca Xcode arkaya gidiyor | `makeKeyAndOrderFront` veya `NSApp.activate()` | `orderFrontRegardless()` kullan |
| Hover çalışmıyor | `acceptsMouseMovedEvents = false` | `true` yap |
| Panel full-screen app'te kayboluyor | collection behavior eksik | `.fullScreenAuxiliary` ekle |
| Genişleyince ekran dışına taşıyor | sabit yön | `expandedFrame` clamp |
| Küçülürken hover event kaybı | fare eski alanda | çıkış gecikmesi + tracking area |
| Metin alanına yazamıyorum | `canBecomeKey = false` | override `true`, alan focus'ta `makeKey()` |
| Sandbox'ta login item çalışmıyor | eski API | `SMAppService.mainApp.register()` |
| Uyku sonrası panel kayboldu | ekran parametreleri değişti | `didChangeScreenParameters` dinle, yeniden konumlandır |
