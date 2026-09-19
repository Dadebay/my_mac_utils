import Foundation
import SwiftData

/// Odak oturumlarının tek başlangıç/bitiş noktası.
///
/// Bir seferde en fazla bir aktif oturum kuralı burada zorlanıyor — UI bunu
/// tekrar uygulamak zorunda değil, yalnızca `.sessionAlreadyActive` hatasını
/// gösterip kullanıcıya onay sorabilir.
@MainActor
public enum FocusSessionService {
    public enum FocusSessionError: LocalizedError, Equatable {
        case sessionAlreadyActive

        public var errorDescription: String? {
            switch self {
            case .sessionAlreadyActive:
                L10n.focusSessionAlreadyActive
            }
        }
    }

    public static func activeSession(in context: ModelContext) -> FocusSession? {
        (try? context.fetch(FetchDescriptor<FocusSession>(predicate: FocusSession.activePredicate())))?.first
    }

    /// Zaten bir aktif oturum varsa `.sessionAlreadyActive` fırlatır —
    /// kullanıcı onaylamadan mevcut oturum kapatılmaz.
    @discardableResult
    public static func start(
        task: Task?,
        duration: FocusDuration,
        in context: ModelContext
    ) throws -> FocusSession {
        guard activeSession(in: context) == nil else {
            throw FocusSessionError.sessionAlreadyActive
        }
        let session = FocusSession(task: task, plannedDurationMinutes: duration.minutes)
        context.insert(session)
        try? context.save()
        return session
    }

    /// Mevcut aktif oturumu `.stopped` olarak kapatıp yenisini başlatır —
    /// kullanıcı onayından sonra çağrılmalı.
    @discardableResult
    public static func forceStart(
        task: Task?,
        duration: FocusDuration,
        in context: ModelContext
    ) -> FocusSession {
        if let active = activeSession(in: context) {
            stop(active, reason: .stopped, in: context)
        }
        let session = FocusSession(task: task, plannedDurationMinutes: duration.minutes)
        context.insert(session)
        try? context.save()
        return session
    }

    public static func stop(_ session: FocusSession, reason: FocusSessionEndReason, in context: ModelContext) {
        guard session.isActive else { return }
        session.endedAt = .now
        session.endedReason = reason
        try? context.save()
    }

    /// Seansı `.completed` olarak kapatır. `completeTask == true` ise
    /// ilişkilendirilmiş görev de tamamlanır — ama bu her zaman ayrı ve
    /// isteğe bağlı bir eylem, otomatik değil.
    public static func complete(_ session: FocusSession, completeTask: Bool, in context: ModelContext) {
        stop(session, reason: .completed, in: context)
        guard completeTask, let task = session.task, !task.isCompleted else { return }
        task.isCompleted = true
        task.completedAt = .now
        TaskRecurrenceService.materializeNextOccurrenceIfNeeded(for: task, in: context)
        try? context.save()
    }

    // MARK: - Geçmiş

    private static func endedSessions(in context: ModelContext) -> [FocusSession] {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { $0.endedAt != nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public static func totalMinutes(in context: ModelContext, since: Date, now: Date = .now) -> Int {
        endedSessions(in: context)
            .filter { ($0.endedAt ?? .distantPast) >= since }
            .reduce(0) { $0 + ($1.actualMinutes ?? 0) }
    }

    public static func todayMinutes(in context: ModelContext, calendar: Calendar = .current, now: Date = .now) -> Int {
        totalMinutes(in: context, since: calendar.startOfDay(for: now), now: now)
    }

    public static func last7DaysMinutes(in context: ModelContext, calendar: Calendar = .current, now: Date = .now) -> Int {
        let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return totalMinutes(in: context, since: start, now: now)
    }

    /// Görev başına toplam dakika, en çok zaman ayrılandan aza sıralı.
    public static func perTaskTotals(in context: ModelContext) -> [(task: Task, minutes: Int)] {
        var totals: [ObjectIdentifier: (task: Task, minutes: Int)] = [:]
        for session in endedSessions(in: context) {
            guard let task = session.task, let minutes = session.actualMinutes else { continue }
            let key = ObjectIdentifier(task)
            totals[key, default: (task, 0)].minutes += minutes
        }
        return totals.values.sorted { $0.minutes > $1.minutes }
    }
}
