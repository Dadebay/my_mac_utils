import Testing
import Foundation
import SwiftData
@testable import GlassDoKit

@MainActor
struct AppContextMatcherTests {
    private func makeContext() throws -> ModelContext {
        let container = try AppStore.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("Eşleşme yoksa boş liste dönüyor")
    func noMatchReturnsEmpty() throws {
        let ctx = try makeContext()
        let task = Task(title: "Xcode'da hata düzelt")
        ctx.insert(task)
        let rule = AppContextRule(bundleIdentifier: "com.apple.dt.Xcode", task: task)
        ctx.insert(rule)
        try ctx.save()

        let matches = AppContextMatcher.matchingTasks(for: "com.figma.Desktop", rules: [rule])
        #expect(matches.isEmpty)
    }

    @Test("Doğrudan görev kuralı eşleşiyor")
    func directTaskRuleMatches() throws {
        let ctx = try makeContext()
        let task = Task(title: "Xcode'da hata düzelt")
        ctx.insert(task)
        let rule = AppContextRule(bundleIdentifier: "com.apple.dt.Xcode", task: task)
        ctx.insert(rule)
        try ctx.save()

        let matches = AppContextMatcher.matchingTasks(for: "com.apple.dt.Xcode", rules: [rule])
        #expect(matches.map(\.id) == [task.id])
    }

    @Test("Etiket kuralı, etiketteki tamamlanmamış tüm görevleri öneriyor")
    func tagRuleMatchesUncompletedTasks() throws {
        let ctx = try makeContext()
        let tag = Tag(name: "geliştirme")
        let open1 = Task(title: "PR incele")
        let open2 = Task(title: "test yaz")
        let done = Task(title: "eski görev")
        done.isCompleted = true
        tag.tasks = [open1, open2, done]
        ctx.insert(tag)
        ctx.insert(open1); ctx.insert(open2); ctx.insert(done)

        let rule = AppContextRule(bundleIdentifier: "com.apple.dt.Xcode", tag: tag)
        ctx.insert(rule)
        try ctx.save()

        let matches = AppContextMatcher.matchingTasks(for: "com.apple.dt.Xcode", rules: [rule])
        #expect(Set(matches.map(\.id)) == Set([open1.id, open2.id]))
        #expect(!matches.contains { $0.id == done.id })
    }

    @Test("Doğrudan görev kuralları etiket kurallarından önce geliyor, sonuç en fazla 3")
    func directRulesComeFirstAndLimitApplies() throws {
        let ctx = try makeContext()
        let tag = Tag(name: "geliştirme")
        let tagged1 = Task(title: "a")
        let tagged2 = Task(title: "b")
        let tagged3 = Task(title: "c")
        tag.tasks = [tagged1, tagged2, tagged3]
        ctx.insert(tag)
        ctx.insert(tagged1); ctx.insert(tagged2); ctx.insert(tagged3)

        let directTask = Task(title: "doğrudan görev")
        ctx.insert(directTask)

        let tagRule = AppContextRule(bundleIdentifier: "com.apple.dt.Xcode", tag: tag, sortIndex: 0)
        let directRule = AppContextRule(bundleIdentifier: "com.apple.dt.Xcode", task: directTask, sortIndex: 1)
        ctx.insert(tagRule)
        ctx.insert(directRule)
        try ctx.save()

        let matches = AppContextMatcher.matchingTasks(
            for: "com.apple.dt.Xcode", rules: [tagRule, directRule], limit: 3
        )
        #expect(matches.count == 3)
        #expect(matches.first?.id == directTask.id)
    }

    @Test("Devre dışı kural eşleşmiyor")
    func disabledRuleIsIgnored() throws {
        let ctx = try makeContext()
        let task = Task(title: "görev")
        ctx.insert(task)
        let rule = AppContextRule(bundleIdentifier: "com.apple.dt.Xcode", task: task)
        rule.isEnabled = false
        ctx.insert(rule)
        try ctx.save()

        let matches = AppContextMatcher.matchingTasks(for: "com.apple.dt.Xcode", rules: [rule])
        #expect(matches.isEmpty)
    }

    @Test("Aktif uygulama nil ise hiçbir şey önerilmiyor")
    func nilBundleIdentifierReturnsEmpty() throws {
        let ctx = try makeContext()
        let task = Task(title: "görev")
        ctx.insert(task)
        let rule = AppContextRule(bundleIdentifier: "com.apple.dt.Xcode", task: task)
        ctx.insert(rule)
        try ctx.save()

        #expect(AppContextMatcher.matchingTasks(for: nil, rules: [rule]).isEmpty)
    }
}
