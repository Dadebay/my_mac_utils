import AppKit

/// Bindirim penceresi — hiçbir zaman anahtar/etkin pencere olmaz (klavye
/// odağını önde duran uygulamadan çalmasın diye — ⌥+Tab'ı yakalayan asıl
/// mekanizma zaten global CGEventTap), ama mouse tıklamalarını kabul eder:
/// bir karta tıklayınca o pencere doğrudan seçilip öne getirilebilir.
final class SwitcherOverlayPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
