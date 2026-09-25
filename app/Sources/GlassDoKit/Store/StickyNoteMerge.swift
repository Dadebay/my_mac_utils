import Foundation
import SwiftData

/// Yapışkan notların kendi satırlarını ana listeye taşıyan tek seferlik geçiş.
///
/// Bir süre her notun kendi satırları vardı (`Task.stickyNote` dolu).
/// Not artık ana listenin kopyası; o dönemde notlara yazılmış satırlar
/// kaybolmasın diye ana listeye geçiyor:
///
/// - Ana listede aynı başlıkla (büyük/küçük harf ve baştaki/sondaki
///   boşluk yok sayılarak) bir görev varsa not satırı çift olmasın diye
///   siliniyor.
/// - Metni olmayan satırlar (ayırıcı, boş satır) taşınmıyor: notun
///   düzenine aitlerdi, ana listenin sonuna gelişigüzel çizgiler eklerdi.
/// - Geri kalanlar nottaki sırasıyla ana listenin sonuna ekleniyor.
///   Tamamlanmış olanlar tamamlanmış kalıyor.
public enum StickyNoteMerge {
    private static let doneKey = "stickyNotes.mergedIntoMainList"

    @MainActor
    public static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        // Geçiş kullanıcının bir eylemi değil: ilk ⌘Z onu geri almamalı.
        context.undoManager?.disableUndoRegistration()
        defer { context.undoManager?.enableUndoRegistration() }
        do {
            try merge(in: context)
            defaults.set(true, forKey: doneKey)
        } catch {
            // Bayrak yazılmıyor: bir sonraki açılışta yeniden deneniyor.
        }
    }

    @MainActor
    static func merge(in context: ModelContext) throws {
        let mainList = try context.fetch(FetchDescriptor<Task>(
            predicate: #Predicate { $0.stickyNote == nil && $0.parentTask == nil }
        ))
        var knownTitles = Set(mainList.map { normalized($0.title) })
        var nextIndex = (mainList.map(\.sortIndex).max() ?? -1) + 1

        let notes = try context.fetch(FetchDescriptor<StickyNote>(sortBy: [SortDescriptor(\.createdAt)]))
        for note in notes {
            for block in note.orderedBlocks {
                let title = normalized(block.title)
                if title.isEmpty || !block.kind.hasText || knownTitles.contains(title) {
                    context.delete(block)
                    continue
                }
                knownTitles.insert(title)
                block.stickyNote = nil
                block.sortIndex = nextIndex
                nextIndex += 1
            }
        }
        try context.save()
    }

    private static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
