import AppKit
import QuartzCore
import SwiftUI
import SwiftData
import GlassDoKit

/// Rayın seçebildiği içerik ile kullanım istatistiğinin özellik kimliği
/// arasındaki eşleme. `.tasks`/`.completed`/`.folders`/`.memory` doğrudan
/// karşılık buluyor; kalanı zaten aynı isimde.
private extension PanelContent {
    var usageFeature: UsageFeature? {
        switch self {
        case .tasks: .tasks
        case .completed: .completed
        case .folders: .folders
        case .memory: .memory
        case .network: .network
        case .battery: .battery
        case .disk: .disk
        case .processor: .processor
        }
    }
}

@MainActor
@Observable
final class EdgePanelController: NSObject, NSWindowDelegate {

    static let bubbleSize: CGFloat = 56
    /// Sabit, görünmez "çapa" dairesinin yarıçapı — ekran kenarında duran,
    /// baloncuğun her zaman bir ucunun bağlı kaldığı öteki uç. Baloncuktan
    /// belirgin küçük: ikinci bir baloncuk değil, kenardan taşan bir
    /// sıvı çıkıntısı gibi okunsun diye.
    static let anchorRadius: CGFloat = bubbleSize * 0.24
    /// Sıvı tuvalinin baloncuğun/çapanın etrafında bıraktığı pay — gölge,
    /// hafif taşma (overshoot) ve kopma anındaki geri çekilme burada
    /// kırpılmadan oynayabilsin diye.
    static let canvasMargin: CGFloat = 30

    private static let topKey = "edgepanel.top"
    private static let edgeKey = "edgepanel.edge"
    private static let modeKey = "edgepanel.mode"
    private static let dockedKey = "edgepanel.isDocked"
    private static let floatingXKey = "edgepanel.floatingX"
    private static let floatingYKey = "edgepanel.floatingY"

    private var panel: EdgePanel?
    private var railTop: CGFloat = 0
    private var floatingOrigin: NSPoint = .zero
    private var sliverTimer: _Concurrency.Task<Void, Never>?
    private var dragStartFrame: NSRect?
    /// Sürükleme başlangıcındaki imleç konumu — EKRAN koordinatlarında.
    /// SwiftUI'ın `DragGesture.translation` değeri pencerenin kendi koordinat
    /// uzayına göre ölçülüyor; her olayda pencereyi hareket ettirdiğimiz için
    /// referans nokta imlecin altında kayıyor ve titreyen, takılan bir geri
    /// besleme döngüsü oluşuyordu. Mutlak imleç konumu bundan etkilenmiyor.
    private var dragStartMouse: NSPoint?
    /// Serbest baloncuk sürüklenirken (`dragStartFrame` artık geçerli
    /// değilken — bkz. `beginDrag`) referans konum bu. Panel çerçevesi
    /// sürüklerken sürekli değiştiği için (dar baloncuktan geniş sıvı
    /// tuvaline) `dragStartFrame`'e güvenmek burada yanlış taban verirdi.
    private var dragStartBubbleCenter: NSPoint?
    /// Bir önceki karenin kenara uzaklığı + zamanı — anlık hız (pt/sn) bunun
    /// farkından hesaplanıyor. Ne kayıtlı bir eğri ne de zamanlayıcı: her
    /// `updateDrag()` çağrısında bir örnek.
    private var lastDistanceSample: (distance: CGFloat, at: Date)?
    /// `endDrag()`'in bırakma kararını (`shouldReattachOnRelease`) verirken
    /// kullandığı son ölçülen hız.
    private var lastOutwardVelocity: CGFloat = 0

    private(set) var visualState: PanelVisualState = .rail
    private(set) var isPanelVisible = false
    private(set) var edge: ScreenEdge = .trailing
    private(set) var isDocked = true
    var content: PanelContent = .tasks

    // MARK: - Sıvı bağlantı durumu (yalnızca `!isDocked` iken anlamlı)

    private(set) var attachment: BubbleAttachment = .attached(edge: .trailing)
    /// Sıvı tuvalinin YEREL (SwiftUI, sol-üst orijinli, y aşağı) koordinat
    /// uzayında çapa ve baloncuk merkezleri — görünüm bunları doğrudan
    /// `MetaballBlobShape`'e veriyor, kendi dönüşümünü yapmıyor.
    private(set) var liquidAnchorCenter: CGPoint = .zero
    private(set) var liquidBubbleCenter: CGPoint = .zero
    /// `nil` = bağlantı yok (tamamen serbest); aksi hâlde 0…1.
    private(set) var liquidPinch: Double?

    /// Ana pencereyi açmak için GlassDoApp tarafından set edilir (gear butonu).
    var openMainWindow: (() -> Void)?
    /// Ayarlar penceresini açmak için GlassDoApp tarafından set edilir (gear butonu).
    var openSettings: (() -> Void)?

    /// `NSScreen.main` odaklı pencereye göre değişir ve panel hiç key olmadığı
    /// için (nonactivating) başlangıçta güvenilmez — çoklu monitörde panel
    /// yanlış ekrana konumlanabilir. Bunun yerine global (0,0) orijinli,
    /// menü çubuğunu taşıyan gerçek birincil ekranı kullan.
    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    var mode: PanelMode = .rail {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            modeChanged()
        }
    }

    func attach(container: ModelContainer, @ViewBuilder content: () -> some View) {
        guard panel == nil else { return }

        mode = PanelMode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .rail
        edge = ScreenEdge(rawValue: UserDefaults.standard.string(forKey: Self.edgeKey) ?? "") ?? .trailing
        isDocked = UserDefaults.standard.object(forKey: Self.dockedKey) as? Bool ?? true
        railTop = restoredTop()
        floatingOrigin = restoredFloatingOrigin()

        if !isDocked {
            resetDetachedLiquidGeometry()
        }

        let visible = Self.primaryScreen?.visibleFrame ?? .zero
        let frame = isDocked
            ? EdgeGeometry.railFrame(edge: edge, top: railTop, height: PanelSettings.railHeight, width: PanelSettings.railWidth, visible: visible)
            : NSRect(origin: floatingOrigin, size: CGSize(width: Self.bubbleSize, height: Self.bubbleSize))

        let panel = EdgePanel(contentRect: frame)
        panel.delegate = self
        let rootView = content()
            .environment(self)
            .modelContainer(container)
        let hostingView = NSHostingView(rootView: rootView)
        // NSHostingView autoresizingMask varsayılan olarak .notSizable —
        // pencere rail'den genişlemiş panele animasyonla büyüyünce, içerik
        // eski (küçük) boyutunda köşede kalıp yuvarlatılmış alanın yalnızca
        // bir kısmını dolduruyordu. .width/.height ile pencereyle birlikte
        // büyümesi sağlanıyor.
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        self.panel = panel

        panel.orderFrontRegardless()
        isPanelVisible = true

        if isDocked {
            if mode == .pinned {
                setExpanded(true)
            } else if mode == .sliver {
                scheduleSliverHide()
            }
        }
    }

    func togglePanelVisibility() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            isPanelVisible = false
        } else {
            panel.orderFrontRegardless()
            isPanelVisible = true
        }
    }

    func setMode(_ newMode: PanelMode) {
        mode = newMode
    }

    private func modeChanged() {
        sliverTimer?.cancel()
        guard isDocked else { return }
        switch mode {
        case .pinned:
            setExpanded(true)
        case .rail:
            if visualState != .expanded { setVisualState(.rail) }
        case .sliver:
            if visualState != .expanded { scheduleSliverHide() }
        }
    }

    // MARK: - İçerik seçimi (rail ikonları — sadece tıklamayla, hover asla açmaz/kapatmaz)

    /// Aynı ikona tekrar tıklarsan kapanır (toggle); farklı bir ikona tıklarsan
    /// içerik değişir ve panel açık kalır. Hover bu akışa hiç dahil değil.
    func selectContent(_ newContent: PanelContent) {
        if content == newContent && visualState == .expanded {
            setExpanded(false)
        } else {
            content = newContent
            setExpanded(true)
            // Yalnız gerçekten açma/geçiş anı sayılıyor — aynı ikona tekrar
            // basıp paneli kapatmak (yukarıdaki dal) yeni bir kullanım değil.
            if let feature = newContent.usageFeature {
                UsageStore.track(feature, source: .edgeRail)
            }
        }
    }

    // MARK: - Expand/collapse

    func setExpanded(_ expand: Bool) {
        guard isDocked else { return }
        if !expand && !PanelPresentation.shouldCollapseOnHoverExit(mode: mode) { return }
        setVisualState(expand ? .expanded : .rail)
        if !expand {
            scheduleSliverHide()
        }
    }

    func reveal() {
        sliverTimer?.cancel()
        guard visualState == .sliver else { return }
        setVisualState(.rail)
    }

    private func setVisualState(_ newState: PanelVisualState) {
        guard let panel, let screen = panel.screen ?? Self.primaryScreen else { return }
        guard newState != visualState else { return }
        visualState = newState

        let visible = screen.visibleFrame
        let railFrame = EdgeGeometry.railFrame(edge: edge, top: railTop, height: PanelSettings.railHeight, width: PanelSettings.railWidth, visible: visible)

        let target: NSRect
        switch newState {
        case .rail:
            target = railFrame
        case .expanded:
            target = EdgeGeometry.expandedFrame(
                railFrame: railFrame, edge: edge,
                panelSize: CGSize(
                    width: PanelSettings.panelWidth,
                    height: PanelSettings.effectivePanelHeight
                ),
                visible: visible
            )
        case .sliver:
            target = EdgeGeometry.sliverFrame(railFrame: railFrame, edge: edge, sliverWidth: EdgeTokens.sliverWidth)
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(target, display: true)
            return
        }

        let isGrowing = target.width > panel.frame.width
        let duration = isGrowing
            ? EdgeTokens.panelExpandDuration
            : EdgeTokens.panelCollapseDuration

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            // Drawer eğrisi: hızlı tepki verir, sona yaklaşırken yumuşar ve
            // spring gibi ekran kenarından taşıp geri sekmez.
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            panel.animator().setFrame(target, display: true)
        }
    }

    // MARK: - Edge peek (sliver mod)

    private func scheduleSliverHide() {
        sliverTimer?.cancel()
        guard PanelPresentation.shouldAutoHideToSliver(mode: mode, isExpanded: visualState == .expanded) else { return }
        sliverTimer = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(for: EdgeTokens.sliverHideDelay)
            guard !_Concurrency.Task.isCancelled else { return }
            self?.setVisualState(.sliver)
        }
    }

    // MARK: - Sürükleme (SwiftUI DragGesture üzerinden — isMovableByWindowBackground
    // cam katmanla güvenilir çalışmadığı için manuel yönetiliyor)
    //
    // Ray kenardan `MetaballZones.bondedDistance` kadar uzağa sürüklenince
    // yuvarlak, sıvı bağlantılı bir baloncuğa "soyulur". Bundan sonraki her
    // kare bu baloncuğun kenara olan canlı mesafesini ve hızını okuyup
    // `attachment`/`liquidPinch`'i günceller — kayıtlı bir animasyon değil,
    // doğrudan sürükleme verisinden hesaplanan geometri. Kenara yeterince
    // yaklaşınca (bırakma anında, momentum projeksiyonuyla) rail'e geri
    // döner.

    func beginDrag() {
        guard visualState != .expanded else { return }
        dragStartMouse = NSEvent.mouseLocation
        lastDistanceSample = nil
        if isDocked {
            dragStartFrame = panel?.frame
            dragStartBubbleCenter = nil
        } else {
            // Baloncuk kopmuşsa (veya kopma/birleşme animasyonu hâlâ
            // sürüyorken tekrar tutulduysa) referans artık panel çerçevesi
            // değil — panel bu sırada dar baloncuktan geniş sıvı tuvaline
            // kadar herhangi bir boyutta olabilir. Baloncuğun kendi bilinen
            // merkezi (`floatingOrigin`) sabit taban.
            dragStartFrame = nil
            dragStartBubbleCenter = NSPoint(
                x: floatingOrigin.x + Self.bubbleSize / 2,
                y: floatingOrigin.y + Self.bubbleSize / 2
            )
        }
    }

    func updateDrag() {
        guard let panel, let startMouse = dragStartMouse else { return }
        let visible = (panel.screen ?? Self.primaryScreen)?.visibleFrame ?? .zero
        let mouse = NSEvent.mouseLocation
        let now = Date()

        if isDocked, let start = dragStartFrame {
            let origin = NSPoint(
                x: start.origin.x + (mouse.x - startMouse.x),
                y: start.origin.y + (mouse.y - startMouse.y)
            )
            let distanceFromEdge = min(origin.x - visible.minX, visible.maxX - origin.x)

            guard distanceFromEdge > MetaballZones.bondedDistance else {
                updateDockedReposition(origin: origin, visible: visible, panel: panel)
                return
            }

            // Soyulma anı: rail'in tam ikon şeridinden yuvarlak baloncuğa
            // dönüşmesi tek, kanıtlanmış bir "pop" — gerçek bir dörtgenden
            // daireye biçim geçişi bu görevin kapsamındaki metaball
            // probleminden ayrı, çok daha büyük bir problem. Bu kareden
            // sonra sürükleme aşağıdaki serbest baloncuk yoluna devrediyor.
            let bubbleCenter = NSPoint(x: origin.x + Self.bubbleSize / 2, y: origin.y + Self.bubbleSize / 2)
            isDocked = false
            dragStartFrame = nil
            dragStartBubbleCenter = bubbleCenter
            dragStartMouse = mouse
            updateFloatingBubble(rawCenter: bubbleCenter, visible: visible, panel: panel, now: now)
            return
        }

        guard let startCenter = dragStartBubbleCenter else { return }
        let bubbleCenter = NSPoint(
            x: startCenter.x + (mouse.x - startMouse.x),
            y: startCenter.y + (mouse.y - startMouse.y)
        )
        updateFloatingBubble(rawCenter: bubbleCenter, visible: visible, panel: panel, now: now)
    }

    /// `isDocked` iken yalnızca kenar boyunca yeniden konumlanma (dikey
    /// sürükleme, kenar değişimi) — sıvı bağlantı sistemine hiç girmiyor.
    private func updateDockedReposition(origin: NSPoint, visible: NSRect, panel: EdgePanel) {
        let clampedTop = EdgeGeometry.clampedTop(origin.y, height: PanelSettings.railHeight, visible: visible)
        let liveEdge = EdgeGeometry.nearestEdge(point: NSPoint(x: origin.x, y: origin.y), visible: visible)
        let edgeChanged = liveEdge != edge
        edge = liveEdge
        railTop = clampedTop
        let railFrame = EdgeGeometry.railFrame(edge: liveEdge, top: clampedTop, height: PanelSettings.railHeight, width: PanelSettings.railWidth, visible: visible)

        if edgeChanged || panel.frame.size != railFrame.size {
            panel.setFrame(railFrame, display: false)
        } else {
            panel.setFrameOrigin(railFrame.origin)
        }
    }

    /// Serbest baloncuğun tek karesi: konumu ekran sınırına kelepçele, en
    /// yakın kenara olan mesafe ve hızı ölç, kenara yeterince yakınsa sıvı
    /// tuvalini büyüt ve bağlantı geometrisini yeniden hesapla — uzaktaysa
    /// tuvali bırak, yalnızca düz baloncuk kalsın.
    private func updateFloatingBubble(rawCenter: NSPoint, visible: NSRect, panel: EdgePanel, now: Date) {
        let half = Self.bubbleSize / 2
        let bubbleCenter = NSPoint(
            x: min(max(rawCenter.x, visible.minX + half), visible.maxX - half),
            y: min(max(rawCenter.y, visible.minY + half), visible.maxY - half)
        )
        floatingOrigin = NSPoint(x: bubbleCenter.x - half, y: bubbleCenter.y - half)

        let nearestEdge = EdgeGeometry.nearestEdge(point: bubbleCenter, visible: visible)
        edge = nearestEdge
        let centerDistanceFromEdge = nearestEdge == .trailing
            ? visible.maxX - bubbleCenter.x
            : bubbleCenter.x - visible.minX
        // Metaball eşikleri merkez mesafesi için değil, dairenin kenarıyla
        // ekran arasındaki gerçek boşluk için tanımlı. Merkez mesafesini
        // kullanmak, flush duran 56 pt baloncuğu daha ilk karede 28 pt
        // gerilmiş sayıyordu.
        let gapFromEdge = max(centerDistanceFromEdge - half, 0)

        var velocity: CGFloat = 0
        if let last = lastDistanceSample {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.0008 { velocity = (gapFromEdge - last.distance) / CGFloat(dt) }
        }
        lastDistanceSample = (gapFromEdge, now)
        lastOutwardVelocity = velocity

        let threshold = MetaballZones.effectiveDetachDistance(outwardVelocity: velocity)
        guard gapFromEdge < threshold + Self.canvasMargin else {
            // Tamamen serbest: sıvı tuvaline gerek yok — gereksiz katman
            // taşımanın karşılığı yok, panel yalnızca baloncuk büyüklüğünde.
            attachment = .detached
            resetDetachedLiquidGeometry()
            setPanelFrame(NSRect(origin: floatingOrigin, size: CGSize(width: Self.bubbleSize, height: Self.bubbleSize)), on: panel)
            return
        }

        let canvas = liquidCanvasFrame(bubbleCenter: bubbleCenter, edge: nearestEdge, visible: visible)
        setPanelFrame(canvas, on: panel)
        let local = liquidLocalPoints(bubbleCenter: bubbleCenter, edge: nearestEdge, canvas: canvas)
        liquidAnchorCenter = local.anchor
        liquidBubbleCenter = local.bubble
        attachment = MetaballZones.classifyDetaching(distance: gapFromEdge, edge: nearestEdge, outwardVelocity: velocity)
        liquidPinch = MetaballZones.progress(distance: gapFromEdge, outwardVelocity: velocity)
    }

    /// Geniş sıvı tuvalinden 56×56 serbest panele dönerken SwiftUI yerel
    /// koordinatını da yeni panelin merkezine taşı. Aksi hâlde içerik eski
    /// geniş tuval koordinatında kalır; cam daire kırpılır ve yalnızca ikonun
    /// küçük bir parçası görünür.
    private func resetDetachedLiquidGeometry() {
        let half = Self.bubbleSize / 2
        liquidAnchorCenter = CGPoint(x: half, y: half)
        liquidBubbleCenter = CGPoint(x: half, y: half)
        liquidPinch = nil
    }

    private func setPanelFrame(_ frame: NSRect, on panel: EdgePanel) {
        if panel.frame.size != frame.size {
            panel.setFrame(frame, display: false)
        } else {
            panel.setFrameOrigin(frame.origin)
        }
    }

    /// Kenara flush, baloncuğun Y'sini izleyen genişletilmiş, şeffaf tuval.
    /// Yalnızca bu dikdörtgenin içi çizilir/tıklanabilir; geri kalan masaüstü
    /// tıklamalarını (`Color.clear.allowsHitTesting(false)` — bkz.
    /// `LiquidBubbleView`) engellemeden geçirir.
    private func liquidCanvasFrame(bubbleCenter: NSPoint, edge: ScreenEdge, visible: NSRect) -> NSRect {
        let half = Self.bubbleSize / 2
        let minY = max(bubbleCenter.y - half - Self.canvasMargin, visible.minY)
        let maxY = min(bubbleCenter.y + half + Self.canvasMargin, visible.maxY)
        switch edge {
        case .trailing:
            let minX = min(bubbleCenter.x - half - Self.canvasMargin, visible.maxX)
            return NSRect(x: minX, y: minY, width: visible.maxX - minX, height: maxY - minY)
        case .leading:
            let maxX = max(bubbleCenter.x + half + Self.canvasMargin, visible.minX)
            return NSRect(x: visible.minX, y: minY, width: maxX - visible.minX, height: maxY - minY)
        }
    }

    /// AppKit (sol-alt orijinli, y yukarı) → SwiftUI yerel (sol-üst orijinli,
    /// y aşağı) dönüşümü. Çapa her zaman tuvalin kenar tarafındaki duvarında,
    /// baloncukla aynı Y'de — dikey sürüklemede de bağlantı hep dik açıda kalır.
    private func liquidLocalPoints(
        bubbleCenter: NSPoint, edge: ScreenEdge, canvas: NSRect
    ) -> (anchor: CGPoint, bubble: CGPoint) {
        let bubbleLocal = CGPoint(x: bubbleCenter.x - canvas.minX, y: canvas.maxY - bubbleCenter.y)
        let anchorX: CGFloat = edge == .trailing ? canvas.width : 0
        return (CGPoint(x: anchorX, y: bubbleLocal.y), bubbleLocal)
    }

    func endDrag() {
        guard dragStartMouse != nil else { return }
        dragStartMouse = nil
        dragStartFrame = nil
        dragStartBubbleCenter = nil
        lastDistanceSample = nil

        if let panel, !isDocked {
            settleFloatingBubble(on: panel)
        }

        persist()
        if isDocked, mode == .sliver { scheduleSliverHide() }
    }

    /// Bırakma anındaki karar: konumun kendisi değil, momentumun taşıyacağı
    /// izdüşüm konum belirliyor (bkz. `MetaballZones.shouldReattachOnRelease`
    /// — Apple'ın *Designing Fluid Interfaces* projeksiyonu). Yavaşça kenara
    /// yakın bırakılan bir baloncuk yapışır; hızla kenardan uzağa savrulan
    /// bir baloncuk — kenara yakın bile olsa — serbest kalır.
    private func settleFloatingBubble(on panel: EdgePanel) {
        guard let screen = panel.screen ?? Self.primaryScreen else { return }
        let visible = screen.visibleFrame
        let half = Self.bubbleSize / 2
        let bubbleCenter = NSPoint(x: floatingOrigin.x + half, y: floatingOrigin.y + half)
        let nearestEdge = EdgeGeometry.nearestEdge(point: bubbleCenter, visible: visible)
        let centerDistance = nearestEdge == .trailing ? visible.maxX - bubbleCenter.x : bubbleCenter.x - visible.minX
        let distance = max(centerDistance - half, 0)

        guard MetaballZones.shouldReattachOnRelease(distance: distance, outwardVelocity: lastOutwardVelocity) else {
            attachment = .detached
            resetDetachedLiquidGeometry()
            popAnimate(panel, to: NSRect(origin: floatingOrigin, size: CGSize(width: Self.bubbleSize, height: Self.bubbleSize)))
            return
        }

        edge = nearestEdge
        attachment = .reattaching(edge: nearestEdge)
        isDocked = true
        railTop = EdgeGeometry.clampedTop(
            bubbleCenter.y - PanelSettings.railHeight / 2, height: PanelSettings.railHeight, visible: visible
        )
        let railFrame = EdgeGeometry.railFrame(
            edge: nearestEdge, top: railTop, height: PanelSettings.railHeight,
            width: PanelSettings.railWidth, visible: visible
        )
        popAnimate(panel, to: railFrame)
        attachment = .attached(edge: nearestEdge)
        liquidPinch = nil
    }

    /// Kopma/yeniden yapışma anındaki "fırlama" hissi veren hafif taşmalı
    /// animasyon. Reduce Motion açıkken taşmasız, anlık — `setVisualState`
    /// ile aynı kural.
    private func popAnimate(_ panel: EdgePanel, to frame: NSRect) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Baloncuk hâlindeyken tıklanınca son bilinen kenara geri döner.
    func redock() {
        guard !isDocked, let panel, let screen = panel.screen ?? Self.primaryScreen else { return }
        isDocked = true
        attachment = .attached(edge: edge)
        liquidPinch = nil
        persist()
        let visible = screen.visibleFrame
        let frame = EdgeGeometry.railFrame(edge: edge, top: railTop, height: PanelSettings.railHeight, width: PanelSettings.railWidth, visible: visible)
        popAnimate(panel, to: frame)
    }

    // MARK: - Kenar / pozisyon kalıcılığı (sistem kaynaklı taşımalar için yedek)

    func windowDidMove(_ notification: Notification) {
        guard let panel, isDocked, visualState != .expanded, dragStartFrame == nil else { return }
        let visible = (panel.screen ?? Self.primaryScreen)?.visibleFrame ?? .zero

        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        edge = EdgeGeometry.nearestEdge(point: center, visible: visible)
        railTop = EdgeGeometry.clampedTop(panel.frame.origin.y, height: panel.frame.height, visible: visible)
        persist()

        let snapped = EdgeGeometry.railFrame(edge: edge, top: railTop, height: panel.frame.height, width: PanelSettings.railWidth, visible: visible)
        panel.setFrame(snapped, display: true)

        if mode == .sliver { scheduleSliverHide() }
    }

    // MARK: - Persistence

    private func restoredTop() -> CGFloat {
        let raw = UserDefaults.standard.double(forKey: Self.topKey)
        guard raw != 0, let visible = Self.primaryScreen?.visibleFrame else {
            let visible = Self.primaryScreen?.visibleFrame ?? .zero
            return EdgeGeometry.clampedTop(visible.maxY - PanelSettings.railHeight - 24, height: PanelSettings.railHeight, visible: visible)
        }
        return EdgeGeometry.clampedTop(raw, height: PanelSettings.railHeight, visible: visible)
    }

    private func restoredFloatingOrigin() -> NSPoint {
        let x = UserDefaults.standard.double(forKey: Self.floatingXKey)
        let y = UserDefaults.standard.double(forKey: Self.floatingYKey)
        guard x != 0 || y != 0, let visible = Self.primaryScreen?.visibleFrame else {
            let visible = Self.primaryScreen?.visibleFrame ?? .zero
            return NSPoint(x: visible.midX - Self.bubbleSize / 2, y: visible.midY - Self.bubbleSize / 2)
        }
        return NSPoint(
            x: min(max(x, visible.minX), visible.maxX - Self.bubbleSize),
            y: min(max(y, visible.minY), visible.maxY - Self.bubbleSize)
        )
    }

    private func persist() {
        UserDefaults.standard.set(isDocked, forKey: Self.dockedKey)
        if isDocked {
            UserDefaults.standard.set(railTop, forKey: Self.topKey)
            UserDefaults.standard.set(edge.rawValue, forKey: Self.edgeKey)
        } else {
            UserDefaults.standard.set(Double(floatingOrigin.x), forKey: Self.floatingXKey)
            UserDefaults.standard.set(Double(floatingOrigin.y), forKey: Self.floatingYKey)
        }
    }
}
