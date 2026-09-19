import Foundation

/// Bir görevin tekrar sıklığı. V1 kapsamı: her gün, her hafta, her ay ve
/// seçilmiş hafta günleri — RRULE veya EventKit bağımlılığı yok.
public enum RecurrenceFrequency: String, Codable, Sendable, CaseIterable, Hashable {
    case daily
    case weekly
    case monthly
    case weekdays

    public var displayName: String {
        switch self {
        case .daily: L10n.s("Her gün", "Every day", "Каждый день")
        case .weekly: L10n.s("Her hafta", "Every week", "Каждую неделю")
        case .monthly: L10n.s("Her ay", "Every month", "Каждый месяц")
        case .weekdays: L10n.s("Seçili günler", "Selected days", "Выбранные дни")
        }
    }
}

/// Küçük, Codable/Sendable bir değer tipi — `Task.recurrenceData` üzerinde
/// JSON olarak saklanır (bkz. `Task.recurrenceRule`).
public struct RecurrenceRule: Codable, Sendable, Equatable {
    public var frequency: RecurrenceFrequency
    /// Yalnızca `.weekdays` için kullanılır. `Calendar` bileşenleriyle aynı
    /// sayım: 1 = Pazar ... 7 = Cumartesi.
    public var weekdays: Set<Int>

    public init(frequency: RecurrenceFrequency, weekdays: Set<Int> = []) {
        self.frequency = frequency
        self.weekdays = weekdays
    }
}
