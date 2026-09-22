import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Panelin SwiftUI içeriğini taşıyan hosting view.
///
/// AppKit'te bir pencere **key değilken** ona gelen ilk tıklama, varsayılan
/// olarak yalnızca pencereyi key yapmak için harcanır; altındaki denetime
/// hiç ulaşmaz (`NSView.acceptsFirstMouse` varsayılan olarak `false`).
/// Kenar paneli sürekli başka bir uygulamanın üstünde yüzdüğü için bu, her
/// geri dönüşte ilk tıklamanın yutulması demekti: kullanıcı görev satırındaki
/// tamamlama dairesine basıyor, hiçbir şey olmuyordu. Panelde klavye odağı
/// gerektirmeyen her denetim (checkbox, ses kaydırıcısı, kapat düğmeleri)
/// aynı hatadan etkileniyordu.
///
/// `true` döndürmek pencere key olma davranışını değiştirmiyor — yalnızca o
/// ilk tıklamanın denetime de iletilmesini sağlıyor.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Tıklamaya açık olan yatay aralık (pencere koordinatında). Pencere
    /// artık açılıp kapanırken boyut değiştirmediği için kapalı hâlde
    /// gövdenin durduğu alan saydam kalıyor; oradaki tıklama pencereye
    /// takılmamalı, arkadaki uygulamaya geçmeli.
    var interactiveRange: (() -> ClosedRange<CGFloat>)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let range = interactiveRange?(), !range.contains(point.x) {
            return nil
        }
        return super.hitTest(point)
    }
}

final class EdgePanel: NSPanel, NSDraggingDestination {

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

        registerShelfDropTypes()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Panel de uygulama önde değilken kullanılıyor: hızlı ekleme alanına
    /// ve pano listesine yapıştırmak aynı nedenle çalışmıyordu
    /// (bkz. `performsTextEditingKeyEquivalent`).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        return performsTextEditingKeyEquivalent(with: event)
    }

    // MARK: - Pencere düzeyinde sürükleme hedefi

    /// Bırakmanın şu an kabul edilip edilmeyeceği (raf sayfası açık mı).
    var shouldAcceptDrop: (() -> Bool)?
    /// Sürükleme panelin üzerine girip çıktığında — görsel geri bildirim için.
    var dropTargetingChanged: ((Bool) -> Void)?
    /// Çözülmüş sağlayıcılarla gerçek içeri aktarma.
    var performDrop: (([NSItemProvider]) -> Bool)?

    /// Sürükleme kaydı neden **görünümde değil pencerede**:
    ///
    /// AppKit sürükleme hedefini `hitTest` ile arıyor. Rafın üstüne konan
    /// AppKit görünümü kayıtlı, pencerede ve tam boyutta olmasına rağmen
    /// `draggingEntered` hiç tetiklenmiyordu — yani sürükleme görünüm
    /// hiyerarşisine hiç ulaşmıyor. `NSWindow`'un kendisi de
    /// `NSDraggingDestination`'a uyuyor ve hiçbir görünüm sürüklemeyi
    /// üstlenmediğinde devreye giriyor; bu yol görünüm hit-test'ine hiç
    /// bağlı değil.
    ///
    /// Ek fayda: üstte tıklamaları yutan bir catcher overlay'e gerek
    /// kalmıyor, yani raftaki kutucuklar tıklanabilir kalıyor.
    private func registerShelfDropTypes() {
        registerForDraggedTypes([
            .fileURL,
            .init(UTType.image.identifier),
            .init(UTType.movie.identifier),
        ])
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard shouldAcceptDrop?() ?? false else {
            return []
        }
        dropTargetingChanged?(true)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        (shouldAcceptDrop?() ?? false) ? .copy : []
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        dropTargetingChanged?(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTargetingChanged?(false)
        guard shouldAcceptDrop?() ?? false else { return false }

        let providers = EdgePanel.itemProviders(from: sender.draggingPasteboard)
        guard !providers.isEmpty else { return false }
        return performDrop?(providers) ?? false
    }

    /// `NSPasteboard.readObjects(forClasses:)` yalnızca `NSPasteboardReading`
    /// uyumlu sınıfları kabul eder — `NSItemProvider` uymuyor, dolayısıyla onu
    /// isteyen çağrı her zaman boş döner. Panodan gerçekten okunabilenleri
    /// okuyup `ShelfImporter`'ın beklediği sağlayıcılara burada çeviriyoruz.
    static func itemProviders(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls.compactMap { NSItemProvider(contentsOf: $0) }
        }

        if let images = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        ) as? [NSImage], !images.isEmpty {
            let name = suggestedName(from: pasteboard)
            return images.map { image in
                let provider = NSItemProvider(object: image)
                // Ad verilmezse `ShelfImporter` "Image"a düşüyor ve rafa
                // eklenen her görsel "Image.png", "Image 2.png" diye
                // birikiyordu — hangisinin ne olduğu ayırt edilemiyordu.
                provider.suggestedName = name
                return provider
            }
        }

        return []
    }

    /// Web sayfasından sürüklenen görselin panosunda dosya yok, ama çoğu
    /// zaman kaynak adres var; ad oradan çıkarılıyor.
    private static func suggestedName(from pasteboard: NSPasteboard) -> String? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let url = urls.first
        else { return nil }

        let raw = url.deletingPathExtension().lastPathComponent
        let decoded = raw.removingPercentEncoding ?? raw
        // Dosya sisteminde ad olarak kullanılamayan ayraçlar temizleniyor.
        let cleaned = decoded
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Kimlik benzeri çok uzun adresler ada dönüşmesin.
        guard !cleaned.isEmpty, cleaned.count <= 60 else { return nil }
        return cleaned
    }
}
