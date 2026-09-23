import AppKit
import SwiftUI
import SwiftData
import GlassDoKit

/// Masaüstündeki yapışkan notları yönetir.
///
/// `DesktopWidgetController` ile aynı desen: tek bir sınıf, pencere
/// sözlüğü, açık olanların kimliği `UserDefaults`'ta. Farkı, pencerelerin
/// sabit türler değil kullanıcının yarattığı notlar olması — aynı anda
/// istenildiği kadar not açılabiliyor.
///
/// Eskiden tek bir pencere vardı ve içeriği ana görev listesiydi
/// (`PoppedNoteController`). Yapışkan not fikri bu değil: notlar
/// birbirinden bağımsız, her biri kendi rengiyle masaüstünde duran
/// kâğıtlar.
@MainActor
@Observable
final class StickyNotesController: NSObject, NSWindowDelegate {
    static let shared = StickyNotesController()

    /// Son oturumda açık kalan notların kimlikleri.
    private static let openKey = "stickyNotes.open"
    private static let defaultSize = NSSize(width: 330, height: 440)
    /// Yeni not, kaynağın biraz sağ altına düşüyor — üst üste binip
    /// kaybolmasın, ama uzağa da gitmesin.
    private static let cascade = CGFloat(26)

    private var container: ModelContainer?
    private var panels: [UUID: PoppedNotePanel] = [:]

    /// Görünümlerin düğme durumunu güncelleyebilmesi için gözlemlenebilir.
    private(set) var openNoteIDs: Set<UUID> = []

    /// Ana penceredeki "ekrana çıkar" düğmesi buna bakıyor.
    var isOpen: Bool { !openNoteIDs.isEmpty }

    private override init() { super.init() }

    /// `NSScreen.main`, hiçbir pencere key olmadığı açılış anında güvenilir
    /// değil — `EdgePanelController.primaryScreen` ile aynı gerekçe.
    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    // MARK: - Kurulum

    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container

        let stored = UserDefaults.standard.stringArray(forKey: Self.openKey) ?? []
        guard !stored.isEmpty else { return }

        let wanted = Set(stored.compactMap(UUID.init(uuidString:)))
        for note in allNotes() where wanted.contains(note.id) {
            open(note)
        }
    }

    // MARK: - Açma ve kapama

    /// Ana penceredeki düğme: açık not varsa hepsini kapatır, yoksa son
    /// notu (hiç yoksa yeni bir tane) açar.
    func toggle() {
        if isOpen {
            for id in openNoteIDs { close(id) }
            return
        }
        if let last = allNotes().last {
            open(last)
        } else {
            createNote()
        }
    }

    func open(_ note: StickyNote) {
        guard let container else { return }

        if let panel = panels[note.id] {
            panel.orderFrontRegardless()
            return
        }

        let panel = PoppedNotePanel(contentRect: frame(for: note))
        panel.delegate = self

        let id = note.id
        panel.contentView = NSHostingView(
            rootView: PoppedNoteView(note: note, onClose: { [weak self] in self?.close(id) })
                .modelContainer(container)
        )

        panels[note.id] = panel
        openNoteIDs.insert(note.id)
        panel.orderFrontRegardless()
        persistOpenList()
    }

    func close(_ id: UUID) {
        guard let panel = panels[id] else { return }
        persistFrame(of: panel, noteID: id)
        panel.orderOut(nil)
        panels[id] = nil
        openNoteIDs.remove(id)
        persistOpenList()
    }

    /// Yeni bir not yaratıp açar. Rengi sıradaki tonu alıyor: arka arkaya
    /// açılan notlar aynı renkte olursa masaüstünde ayırt edilemiyorlar.
    func createNote(near source: StickyNote? = nil) {
        guard let container else { return }
        let context = container.mainContext

        let existing = allNotes()
        let note = StickyNote(tintRaw: NoteTint.allCases[existing.count % NoteTint.allCases.count].rawValue)

        if let source, let panel = panels[source.id] {
            let origin = panel.frame
            note.frameString = NSStringFromRect(
                NSRect(
                    x: origin.minX + Self.cascade,
                    y: origin.minY - Self.cascade,
                    width: origin.width,
                    height: origin.height
                )
            )
        }

        context.insert(note)
        try? context.save()
        open(note)
    }

    /// Notu ve satırlarını siler, penceresini kapatır.
    func delete(_ note: StickyNote) {
        guard let container else { return }
        close(note.id)
        container.mainContext.delete(note)
        try? container.mainContext.save()
    }

    // MARK: - NSWindowDelegate

    /// Pencere kapandığında açık not listesi **yazılmıyor**.
    ///
    /// Uygulama kapanırken bütün pencereler kapanıyor ve bu yol işlese
    /// listeyi boşaltıyordu: bir sonraki açılışta hiçbir not geri
    /// gelmiyordu. Liste yalnızca kullanıcı bir notu açtığında ya da
    /// kapattığında güncelleniyor (`open` / `close`); kapanışta son
    /// bilinen hâli kalıyor.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? PoppedNotePanel,
              let id = noteID(of: closing) else { return }
        persistFrame(of: closing, noteID: id)
        panels[id] = nil
        openNoteIDs.remove(id)
    }

    func windowDidMove(_ notification: Notification) {
        guard let moved = notification.object as? PoppedNotePanel,
              let id = noteID(of: moved) else { return }
        persistFrame(of: moved, noteID: id)
    }

    func windowDidResize(_ notification: Notification) {
        guard let resized = notification.object as? PoppedNotePanel,
              let id = noteID(of: resized) else { return }
        persistFrame(of: resized, noteID: id)
    }

    // MARK: - Yardımcılar

    private func allNotes() -> [StickyNote] {
        guard let container else { return [] }
        let descriptor = FetchDescriptor<StickyNote>(sortBy: [SortDescriptor(\StickyNote.createdAt)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    private func noteID(of panel: PoppedNotePanel) -> UUID? {
        panels.first(where: { $0.value === panel })?.key
    }

    private func persistOpenList() {
        UserDefaults.standard.set(openNoteIDs.map(\.uuidString), forKey: Self.openKey)
    }

    /// Notun ekrandaki yeri notun kendisinde saklanıyor: pencere kapanıp
    /// açılınca aynı yerde beliriyor, başka bir Mac'e taşınırsa da
    /// notla birlikte gidiyor.
    private func persistFrame(of panel: PoppedNotePanel, noteID: UUID) {
        guard let container else { return }
        guard let note = allNotes().first(where: { $0.id == noteID }) else { return }
        note.frameString = NSStringFromRect(panel.frame)
        try? container.mainContext.save()
    }

    private func frame(for note: StickyNote) -> NSRect {
        let visible = Self.primaryScreen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        if !note.frameString.isEmpty {
            let rect = NSRectFromString(note.frameString)
            // Ekran düzeni değiştiyse ekran dışında kalmış notu geri çek.
            if rect.width > 0, rect.height > 0, visible.intersects(rect) {
                return rect
            }
        }

        /* İlk not sağ kenara yaslanıyor; sonrakiler açık not sayısı kadar
           kaydırılıyor ki üst üste binmesinler. */
        let step = CGFloat(panels.count) * Self.cascade
        return NSRect(
            x: visible.maxX - Self.defaultSize.width - 40 - step,
            y: visible.midY - Self.defaultSize.height / 2 - step,
            width: Self.defaultSize.width,
            height: Self.defaultSize.height
        )
    }
}
