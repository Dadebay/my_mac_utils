import Testing
import Foundation
import SwiftData
@testable import GlassDoKit

@MainActor
struct FocusSessionServiceTests {
    private func makeContext() throws -> ModelContext {
        let container = try AppStore.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("Kalan süre startedAt'tan hesaplanıyor, ayrı saklanmıyor")
    func remainingSecondsIsComputedFromStartedAt() throws {
        let ctx = try makeContext()
        let task = Task(title: "rapor yaz")
        ctx.insert(task)
        try ctx.save()

        let session = try FocusSessionService.start(task: task, duration: .short, in: ctx)
        let tenMinutesLater = session.startedAt.addingTimeInterval(10 * 60)

        #expect(session.remainingSeconds(now: tenMinutesLater) == 15 * 60)
        #expect(session.isExpired(now: session.startedAt.addingTimeInterval(26 * 60)))
    }

    @Test("Aktif oturum varken ikinci start .sessionAlreadyActive fırlatıyor")
    func secondStartThrowsWhileActive() throws {
        let ctx = try makeContext()
        let task = Task(title: "rapor yaz")
        ctx.insert(task)
        try ctx.save()

        _ = try FocusSessionService.start(task: task, duration: .short, in: ctx)

        #expect(throws: FocusSessionService.FocusSessionError.sessionAlreadyActive) {
            try FocusSessionService.start(task: task, duration: .medium, in: ctx)
        }
    }

    @Test("forceStart mevcut oturumu .stopped olarak kapatıp yenisini başlatıyor")
    func forceStartStopsPreviousSession() throws {
        let ctx = try makeContext()
        let task = Task(title: "rapor yaz")
        ctx.insert(task)
        try ctx.save()

        let first = try FocusSessionService.start(task: task, duration: .short, in: ctx)
        let second = FocusSessionService.forceStart(task: task, duration: .medium, in: ctx)

        #expect(first.isActive == false)
        #expect(first.endedReason == .stopped)
        #expect(second.isActive)
        #expect(FocusSessionService.activeSession(in: ctx)?.id == second.id)
    }

    @Test("complete(completeTask: true) ilişkili görevi de tamamlıyor, false ise dokunmuyor")
    func completeOptionallyCompletesTask() throws {
        let ctx = try makeContext()
        let task = Task(title: "rapor yaz")
        ctx.insert(task)
        try ctx.save()

        let session = try FocusSessionService.start(task: task, duration: .short, in: ctx)
        FocusSessionService.complete(session, completeTask: false, in: ctx)
        #expect(task.isCompleted == false)
        #expect(session.endedReason == .completed)

        let task2 = Task(title: "ikinci görev")
        ctx.insert(task2)
        try ctx.save()
        let session2 = try FocusSessionService.start(task: task2, duration: .short, in: ctx)
        FocusSessionService.complete(session2, completeTask: true, in: ctx)
        #expect(task2.isCompleted)
    }

    @Test("Süresi biten seans yalnızca bir kez tamamlanıyor ve geçmişte doğru dakika görünüyor")
    func historyReflectsCompletedSessionOnce() throws {
        let ctx = try makeContext()
        let task = Task(title: "rapor yaz")
        ctx.insert(task)
        try ctx.save()

        let session = try FocusSessionService.start(task: task, duration: .short, in: ctx)
        session.startedAt = Date().addingTimeInterval(-30 * 60)
        FocusSessionService.complete(session, completeTask: false, in: ctx)

        #expect(session.actualMinutes == 30)
        #expect(FocusSessionService.todayMinutes(in: ctx) == 30)

        // Tekrar complete çağırmak (zaten kapalı) ikinci kez saymamalı.
        FocusSessionService.complete(session, completeTask: false, in: ctx)
        #expect(FocusSessionService.todayMinutes(in: ctx) == 30)
    }

    @Test("Görev başına toplam dakika doğru toplanıyor")
    func perTaskTotalsAggregate() throws {
        let ctx = try makeContext()
        let task = Task(title: "rapor yaz")
        ctx.insert(task)
        try ctx.save()

        let first = try FocusSessionService.start(task: task, duration: .short, in: ctx)
        first.startedAt = Date().addingTimeInterval(-25 * 60)
        FocusSessionService.complete(first, completeTask: false, in: ctx)

        let second = try FocusSessionService.start(task: task, duration: .medium, in: ctx)
        second.startedAt = Date().addingTimeInterval(-10 * 60)
        FocusSessionService.stop(second, reason: .stopped, in: ctx)

        let totals = FocusSessionService.perTaskTotals(in: ctx)
        #expect(totals.count == 1)
        #expect(totals.first?.minutes == 35)
    }
}
