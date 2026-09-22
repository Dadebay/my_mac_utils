import AppKit
import SwiftUI
import SwiftData
import GlassDoKit

/// Görev listesini ekrana "çıkarılmış" tek bir yapışkan not penceresi olarak
/// gösterir. Konumu ve açık kalma durumu hatırlanır.
@MainActor
@Observable
final class PoppedNoteController: NSObject, NSWindowDelegate {

    private static let isOpenKey = "poppedNote.isOpen"
    private static let frameKey = "poppedNote.frame"
    private static let defaultSize = NSSize(width: 330, height: 440)

    private var container: ModelContainer?
    private var panel: PoppedNotePanel?

    /// Görünümlerin düğme durumunu güncelleyebilmesi için gözlemlenebilir.
    private(set) var isOpen = false

    /// `NSScreen.main`, hiçbir pencere key olmadığı başlangıç anında (ya da
    /// çoklu monitörde) güvenilir değil — bkz. `EdgePanelController.primaryScreen`
    /// ile aynı gerekçe. Not, ilk açılışta bu yüzden ekran dışında, görünmez
    /// bir konumda oluşturuluyordu. Menü çubuğunu taşıyan gerçek birincil
    /// ekranı kullan.
    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        if UserDefaults.standard.bool(forKey: Self.isOpenKey) {
            open()
        }
    }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard let container else { return }

        if let panel {
            panel.orderFrontRegardless()
            isOpen = true
            return
        }

        let newPanel = PoppedNotePanel(contentRect: restoredFrame())
        newPanel.delegate = self

        let hostingView = NSHostingView(
            rootView: PoppedNoteView(onClose: { [weak self] in self?.close() })
                .modelContainer(container)
        )
        hostingView.autoresizingMask = [.width, .height]
        newPanel.contentView = hostingView

        panel = newPanel
        isOpen = true
        newPanel.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: Self.isOpenKey)
    }

    func close() {
        guard let panel else { return }
        persistFrame(panel)
        panel.orderOut(nil)
        self.panel = nil
        isOpen = false
        UserDefaults.standard.set(false, forKey: Self.isOpenKey)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? PoppedNotePanel, closing === panel else { return }
        persistFrame(closing)
        panel = nil
        isOpen = false
        UserDefaults.standard.set(false, forKey: Self.isOpenKey)
    }

    func windowDidMove(_ notification: Notification) {
        guard let moved = notification.object as? PoppedNotePanel else { return }
        persistFrame(moved)
    }

    func windowDidResize(_ notification: Notification) {
        guard let resized = notification.object as? PoppedNotePanel else { return }
        persistFrame(resized)
    }

    // MARK: - Konum kalıcılığı

    private func restoredFrame() -> NSRect {
        let visible = Self.primaryScreen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        if let stored = UserDefaults.standard.string(forKey: Self.frameKey) {
            let rect = NSRectFromString(stored)
            // Ekran düzeni değiştiyse ekran dışında kalmış notu geri çek.
            if rect.width > 0, rect.height > 0, visible.intersects(rect) {
                return rect
            }
        }

        return NSRect(
            x: visible.maxX - Self.defaultSize.width - 40,
            y: visible.midY - Self.defaultSize.height / 2,
            width: Self.defaultSize.width,
            height: Self.defaultSize.height
        )
    }

    private func persistFrame(_ panel: PoppedNotePanel) {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }
}
