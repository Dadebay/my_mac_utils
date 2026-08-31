import AppKit

final class EdgePanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Cam katman (GlassEffectContainer) tüm hit-testi kendi üstüne alıyor,
        // bu yüzden isMovableByWindowBackground güvenilir çalışmıyor — sürükleme
        // EdgeRailView'daki DragGesture ile elle yönetiliyor.
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
