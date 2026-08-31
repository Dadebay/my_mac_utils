import SwiftData

public enum AppStore {
    public static let appGroupID = "group.com.dadebay.glassdo"
    public static let cloudKitID = "iCloud.com.dadebay.glassdo"

    @MainActor
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Task.self, Tag.self, FolderBookmark.self])

        let config: ModelConfiguration = if inMemory {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            ModelConfiguration(schema: schema)
        }

        let container = try ModelContainer(for: schema, configurations: [config])
        if !inMemory {
            SeedData.populateIfNeeded(container: container)
        }
        return container
    }
}
