import Testing
import SwiftData
@testable import GlassDoKit

@MainActor
struct SeedDataTests {

    @Test("Local container kuruluyor ve seed data doluyor")
    func localContainerSeeds() throws {
        let schema = Schema([Task.self, Tag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        SeedData.populateIfNeeded(container: container)

        let context = container.mainContext
        let tasks = try context.fetch(FetchDescriptor<Task>())

        #expect(tasks.count == SeedData.tasks.count)
    }

    @Test("Boş olmayan store'a tekrar seed atılmıyor")
    func seedIsIdempotent() throws {
        let schema = Schema([Task.self, Tag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        SeedData.populateIfNeeded(container: container)
        SeedData.populateIfNeeded(container: container)

        let context = container.mainContext
        let tasks = try context.fetch(FetchDescriptor<Task>())
        #expect(tasks.count == SeedData.tasks.count)
    }
}
