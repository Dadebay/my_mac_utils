import SwiftUI
import GlassDoKit

enum SmartList: String, CaseIterable, Identifiable, Hashable {
    case active, completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: L10n.activeTasks
        case .completed: L10n.completedTasks
        }
    }

    var symbolName: String {
        switch self {
        case .active: "checklist"
        case .completed: "checkmark.circle"
        }
    }

    var tint: [Color] {
        switch self {
        case .active:
            [Color(red: 0.24, green: 0.58, blue: 1.0), Color(red: 0.12, green: 0.38, blue: 0.9)]
        case .completed:
            [Color(red: 0.30, green: 0.78, blue: 0.45), Color(red: 0.18, green: 0.58, blue: 0.34)]
        }
    }
}
