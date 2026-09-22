import Testing
import Foundation
import SwiftData
@testable import GlassDoKit

@MainActor
struct TaskHierarchyTests {
    private func makeContext() throws -> ModelContext {
        let container = try AppStore.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("Alt görev eklenince üst görevin subtasks listesinde görünüyor")
    func inverseRelationshipPopulates() throws {
        let ctx = try makeContext()
        let parent = Task(title: "vergi beyanı")
        let child = Task(title: "makbuzları topla")
        child.parentTask = parent
        ctx.insert(parent)
        ctx.insert(child)
        try ctx.save()

        #expect(parent.subtasks?.count == 1)
        #expect(parent.subtasks?.first?.title == "makbuzları topla")
        #expect(child.parentTask === parent)
    }

    @Test("Aktif filtre alt görevleri bağımsız satır olarak döndürmüyor")
    func activePredicateExcludesSubtasks() throws {
        let ctx = try makeContext()
        let parent = Task(title: "vergi beyanı")
        let child = Task(title: "makbuzları topla")
        child.parentTask = parent
        ctx.insert(parent)
        ctx.insert(child)
        try ctx.save()

        let results = try ctx.fetch(FetchDescriptor<Task>(predicate: Task.activePredicate()))
        #expect(results.count == 1)
        #expect(results.first?.title == "vergi beyanı")
    }

    @Test("Üst görev silinince alt görevler de siliniyor (cascade)")
    func cascadeDeleteRemovesSubtasks() throws {
        let ctx = try makeContext()
        let parent = Task(title: "vergi beyanı")
        let child = Task(title: "makbuzları topla")
        child.parentTask = parent
        ctx.insert(parent)
        ctx.insert(child)
        try ctx.save()

        ctx.delete(parent)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Task>())
        #expect(remaining.isEmpty)
    }

    @Test("Haftalık tekrarlayan görev tamamlanınca tek bir sonraki örnek üretiliyor")
    func recurrenceCompletionCreatesSingleNextInstance() throws {
        let ctx = try makeContext()
        let task = Task(title: "haftalık rapor")
        task.dueDate = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 8, hour: 9))
        task.recurrenceRule = RecurrenceRule(frequency: .weekly)
        ctx.insert(task)
        try ctx.save()

        task.isCompleted = true
        task.completedAt = .now
        TaskRecurrenceService.materializeNextOccurrenceIfNeeded(for: task, in: ctx)
        try ctx.save()

        let active = try ctx.fetch(FetchDescriptor<Task>(predicate: Task.activePredicate()))
        #expect(active.count == 1)
        let nextDay = Calendar.current.component(.day, from: active.first!.dueDate!)
        #expect(nextDay == 15)

        // İkinci kez çağırmak (ör. tekrar tamamlama akışı) tamamlanmış
        // görev üzerinde tetiklenmediği için ikinci bir örnek üretmemeli.
        let second = TaskRecurrenceService.materializeNextOccurrenceIfNeeded(for: task, in: ctx)
        #expect(second == nil)
        let stillActive = try ctx.fetch(FetchDescriptor<Task>(predicate: Task.activePredicate()))
        #expect(stillActive.count == 1)
    }
}
