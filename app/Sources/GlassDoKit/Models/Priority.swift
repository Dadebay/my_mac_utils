import Foundation

/// Bir görevin öncelik derecesi. Ham `Int` değeri `Task.priorityRaw` üzerinde
/// saklanır — bkz. `TaskKind` ile aynı desen.
public enum Priority: Int, CaseIterable, Sendable, Identifiable, Hashable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    public var id: Int { rawValue }

    public var symbolName: String {
        switch self {
        case .none: "minus"
        case .low: "flag"
        case .medium: "flag.fill"
        case .high: "exclamationmark.2"
        }
    }

    public var displayName: String {
        switch self {
        case .none: L10n.s("Öncelik yok", "No priority", "Без приоритета")
        case .low: L10n.s("Düşük", "Low", "Низкий")
        case .medium: L10n.s("Orta", "Medium", "Средний")
        case .high: L10n.s("Yüksek", "High", "Высокий")
        }
    }
}
