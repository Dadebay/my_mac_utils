import SwiftData
import Foundation

/// Bir odak oturumunun nasıl sona erdiği.
public enum FocusSessionEndReason: String, Sendable, CaseIterable {
    /// Kullanıcı "Tamamla" dedi.
    case completed
    /// Kullanıcı süresi dolmadan durdurdu.
    case stopped
    /// Süre doldu, kullanıcı hiçbir eylemde bulunmadı.
    case expired
}

/// Sabit süre seçenekleri — V1'de özel süre yok.
public enum FocusDuration: Int, CaseIterable, Sendable, Identifiable {
    case short = 25
    case medium = 50
    case long = 90

    public var id: Int { rawValue }
    public var minutes: Int { rawValue }
}

/// Bir göreve bağlı odak oturumu.
///
/// Kalan süre hiçbir yerde ayrıca saklanmıyor — her zaman `startedAt` ve
/// `plannedDurationMinutes`'ten hesaplanıyor. Böylece uygulama kapanıp
/// açıldığında da doğru kalır; sürekli çalışan bir arka plan timer'ı yok.
@Model
public final class FocusSession {
    public var id: UUID = UUID()
    public var task: Task?
    public var startedAt: Date = Date()
    public var endedAt: Date?
    public var plannedDurationMinutes: Int = FocusDuration.short.minutes
    public var endedReasonRaw: String?

    public init(task: Task?, plannedDurationMinutes: Int) {
        self.task = task
        self.plannedDurationMinutes = plannedDurationMinutes
    }
}

public extension FocusSession {
    var endedReason: FocusSessionEndReason? {
        get { endedReasonRaw.flatMap(FocusSessionEndReason.init(rawValue:)) }
        set { endedReasonRaw = newValue?.rawValue }
    }

    var isActive: Bool { endedAt == nil }

    var plannedDuration: TimeInterval { TimeInterval(plannedDurationMinutes * 60) }

    /// `now` verilmezse `.now` kullanılır — testlerde sabit bir tarih vermek için var.
    func remainingSeconds(now: Date = .now) -> TimeInterval {
        let elapsed = now.timeIntervalSince(startedAt)
        return max(plannedDuration - elapsed, 0)
    }

    func isExpired(now: Date = .now) -> Bool {
        isActive && remainingSeconds(now: now) <= 0
    }

    /// Bitmiş bir oturumun gerçekte ne kadar sürdüğü (dakika). Aktif bir
    /// oturumda `nil` döner — geçmiş yalnızca kapanmış oturumları sayar.
    var actualMinutes: Int? {
        guard let endedAt else { return nil }
        return max(Int(endedAt.timeIntervalSince(startedAt) / 60), 0)
    }
}

public extension FocusSession {
    static func activePredicate() -> Predicate<FocusSession> {
        #Predicate<FocusSession> { session in session.endedAt == nil }
    }
}
