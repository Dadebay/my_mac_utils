import AppKit
import SwiftUI

/// Masaüstüne çıkarılmış ölçer pencerelerini yönetir.
///
/// `PoppedNoteController` ile aynı desen; farkı aynı anda birden çok
/// pencere tutması. Her tür en fazla bir kez açılabiliyor: aynı kartın iki
/// kopyası ekranda dururken hangisinin hangisi olduğu okunmazdı — ikinci
/// kez "çıkar" denince var olan pencere öne geliyor.
@MainActor
@Observable
final class DesktopWidgetController {
    static let shared = DesktopWidgetController()

    private static let openKey = "desktopWidgets.open"
    private static func frameKey(_ kind: DesktopWidgetKind) -> String {
        "desktopWidgets.frame.\(kind.rawValue)"
    }

    private var panels: [DesktopWidgetKind: DesktopWidgetPanel] = [:]
    private var observers: [DesktopWidgetKind: [NSObjectProtocol]] = [:]

    /// Görünümlerin düğme durumunu güncelleyebilmesi için gözlemlenebilir.
    private(set) var openKinds: Set<DesktopWidgetKind> = []

    private init() {}

    /// `NSScreen.main` hiçbir pencere key değilken güvenilir değil —
    /// `EdgePanelController.primaryScreen` ile aynı gerekçe.
    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Uygulama açılışında son oturumdaki widget'ları geri getirir.
    func restore() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.openKey) ?? []
        for raw in stored {
            guard let kind = DesktopWidgetKind(rawValue: raw) else { continue }
            open(kind)
        }
    }

    func isOpen(_ kind: DesktopWidgetKind) -> Bool {
        openKinds.contains(kind)
    }

    func toggle(_ kind: DesktopWidgetKind) {
        isOpen(kind) ? close(kind) : open(kind)
    }

    func open(_ kind: DesktopWidgetKind) {
        if let existing = panels[kind] {
            existing.orderFrontRegardless()
            return
        }

        let panel = DesktopWidgetPanel(contentRect: restoredFrame(for: kind))

        let hostingView = NSHostingView(
            rootView: DesktopWidgetView(kind: kind) { [weak self] in
                self?.close(kind)
            }
        )
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        // `NSWindowDelegate` yerine bildirim: tek bir delege nesnesi yedi
        // pencereyi ayırt etmek için her geri çağırmada sözlükte arama
        // yapmak zorunda kalırdı.
        let center = NotificationCenter.default
        let moved = center.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.persistFrame(of: kind) }
        }
        let resized = center.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.persistFrame(of: kind) }
        }
        observers[kind] = [moved, resized]

        panels[kind] = panel
        openKinds.insert(kind)
        panel.orderFrontRegardless()
        persistOpenKinds()
    }

    func close(_ kind: DesktopWidgetKind) {
        guard let panel = panels[kind] else { return }
        persistFrame(of: kind)

        for observer in observers[kind] ?? [] {
            NotificationCenter.default.removeObserver(observer)
        }
        observers[kind] = nil

        panel.orderOut(nil)
        panel.contentView = nil
        panels[kind] = nil
        openKinds.remove(kind)
        persistOpenKinds()
    }

    func closeAll() {
        for kind in panels.keys { close(kind) }
    }

    // MARK: - Konum kalıcılığı

    private func persistOpenKinds() {
        UserDefaults.standard.set(openKinds.map(\.rawValue).sorted(), forKey: Self.openKey)
    }

    private func persistFrame(of kind: DesktopWidgetKind) {
        guard let panel = panels[kind] else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey(kind))
    }

    /// Kayıtlı konum ekran dışında kalmışsa (monitör değişti, çözünürlük
    /// düştü) widget geri çekiliyor — aksi hâlde kullanıcı açtığı pencereyi
    /// hiç göremezdi.
    private func restoredFrame(for kind: DesktopWidgetKind) -> NSRect {
        let visible = Self.primaryScreen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = kind.defaultSize

        if let stored = UserDefaults.standard.string(forKey: Self.frameKey(kind)) {
            let rect = NSRectFromString(stored)
            if rect.width > 0, rect.height > 0, visible.intersects(rect) {
                return rect
            }
        }

        // Açılan her yeni widget bir öncekinin biraz altına/sağına düşüyor
        // ki üst üste binip tek bir pencere gibi görünmesinler.
        let step = CGFloat(openKinds.count) * 28
        return NSRect(
            x: min(visible.maxX - size.width - 40 + step, visible.maxX - size.width - 8),
            y: max(visible.maxY - size.height - 60 - step, visible.minY + 8),
            width: size.width,
            height: size.height
        )
    }
}
