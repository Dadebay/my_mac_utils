import Testing
import SwiftData
@testable import GlassDoKit

@MainActor
struct TaskTests {

    private func makeContext() throws -> ModelContext {
        let container = try AppStore.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("Görev tamamlanınca completedAt doluyor")
    func completion() throws {
        let ctx = try makeContext()
        let task = Task(title: "provider kod")
        ctx.insert(task)

        task.isCompleted = true
        task.completedAt = .now

        #expect(task.isCompleted)
        #expect(task.completedAt != nil)
    }

    @Test("Aktif filtresi tamamlananları dışlıyor")
    func activeFilter() throws {
        let ctx = try makeContext()
        let open = Task(title: "açık")
        let done = Task(title: "kapalı"); done.isCompleted = true
        ctx.insert(open); ctx.insert(done)

        let results = try ctx.fetch(
            FetchDescriptor<Task>(predicate: Task.activePredicate())
        )
        #expect(results.count == 1)
        #expect(results.first?.title == "açık")
    }

    @Test("Tamamlanan filtresi sadece tamamlananları getiriyor")
    func completedFilter() throws {
        let ctx = try makeContext()
        let open = Task(title: "açık")
        let done = Task(title: "kapalı"); done.isCompleted = true
        ctx.insert(open); ctx.insert(done)

        let results = try ctx.fetch(
            FetchDescriptor<Task>(predicate: Task.completedPredicate())
        )
        #expect(results.count == 1)
        #expect(results.first?.title == "kapalı")
    }
}
