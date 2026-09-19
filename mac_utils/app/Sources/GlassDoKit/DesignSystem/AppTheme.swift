import SwiftUI

public enum AppTheme: String, CaseIterable, Sendable {
    case system, light, dark

    public static let storageKey = "app.theme"

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var displayName: String {
        switch self {
        case .system: L10n.s("Sistem", "System", "Система")
        case .light: L10n.s("Açık", "Light", "Светлая")
        case .dark: L10n.s("Koyu", "Dark", "Тёмная")
        }
    }
}
