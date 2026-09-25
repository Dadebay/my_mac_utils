import Foundation
import SwiftData

public enum AppStore {
    public static let appGroupID = "group.com.dadebay.glassdo"
    public static let cloudKitID = "iCloud.com.dadebay.glassdo"

    @MainActor
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            Task.self, Tag.self, FolderBookmark.self, TaskAttachment.self,
            FocusSession.self, AppContextRule.self, StickyNote.self,
        ])

        let config: ModelConfiguration = if inMemory {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            ModelConfiguration(schema: schema)
        }

        let container = try ModelContainer(for: schema, configurations: [config])

        /*
         * Geri alma veri katmanında.
         *
         * Metin görünümünün kendi geri alma yığını bu uygulamada
         * çalışmıyordu: nottaki her tuş vuruşu bir model değişikliği
         * yaratıyor, model değişince belge baştan kuruluyor ve kurulan
         * belgenin yığını eski aralıkları gösterdiği için temizlenmek
         * zorundaydı. Sonuç, sürekli boşalan bir yığın ve çalışmayan
         * bir ⌘Z.
         *
         * Modelin kendi yöneticisi bu sorunu yaşamıyor: satır eklemek,
         * silmek, tik atmak, metni değiştirmek — hepsi aynı yerde
         * kaydediliyor.
         */
        container.mainContext.undoManager = UndoManager()
        if !inMemory {
            SeedData.populateIfNeeded(container: container)
        }
        return container
    }
}
