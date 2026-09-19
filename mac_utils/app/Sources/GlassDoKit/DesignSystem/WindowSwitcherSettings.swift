import Foundation
import CoreGraphics

/// Pencere değiştiriciyi tetikleyen basılı tutulan tuş — kullanıcı
/// Ayarlar'dan değiştirebilir.
public enum SwitcherModifier: String, CaseIterable, Sendable {
    case option, control, command, shift

    public var eventFlag: CGEventFlags {
        switch self {
        case .option: .maskAlternate
        case .control: .maskControl
        case .command: .maskCommand
        case .shift: .maskShift
        }
    }

    public var symbol: String {
        switch self {
        case .option: "⌥"
        case .control: "⌃"
        case .command: "⌘"
        case .shift: "⇧"
        }
    }

    public var displayName: String {
        switch self {
        case .option: "Option"
        case .control: "Control"
        case .command: "Command"
        case .shift: "Shift"
        }
    }
}

public enum WindowSwitcherSettings {
    public static let modifierKey = "switcher.modifier"
    public static let triggerKeyCodeKey = "switcher.triggerKeyCode"
    public static let triggerKeyLabelKey = "switcher.triggerKeyLabel"
    public static let previewDurationKey = "switcher.previewDuration"
    public static let apparitionDelayKey = "switcher.apparitionDelayMs"
    public static let fadeOutEnabledKey = "switcher.fadeOutEnabled"
    public static let fadeInPreviewEnabledKey = "switcher.fadeInPreviewEnabled"

    public static let defaultModifier: SwitcherModifier = .option
    public static let defaultTriggerKeyCode = 48 // Tab
    public static let defaultTriggerKeyLabel = "Tab"
    public static let defaultPreviewDuration: Double = 2.5
    public static let defaultApparitionDelayMs: Double = 100
    public static let defaultFadeOutEnabled = false
    public static let defaultFadeInPreviewEnabled = true

    public static let previewDurationRange: ClosedRange<Double> = 1...6
    public static let apparitionDelayRange: ClosedRange<Double> = 0...500

    public static var modifier: SwitcherModifier {
        SwitcherModifier(rawValue: UserDefaults.standard.string(forKey: modifierKey) ?? "") ?? defaultModifier
    }

    public static var triggerKeyCode: Int64 {
        let stored = UserDefaults.standard.object(forKey: triggerKeyCodeKey) as? Int
        return Int64(stored ?? defaultTriggerKeyCode)
    }

    public static var triggerKeyLabel: String {
        UserDefaults.standard.string(forKey: triggerKeyLabelKey) ?? defaultTriggerKeyLabel
    }

    public static var previewDuration: Double {
        let stored = UserDefaults.standard.object(forKey: previewDurationKey) as? Double
        return stored ?? defaultPreviewDuration
    }

    /// Bindirim tetiklenince ekranda belirmeden önceki gecikme (ms) —
    /// çok hızlı ⌥+Tab'lerde bindirimin göz kırpması yerine sessizce
    /// atlanmasını sağlar.
    public static var apparitionDelayMs: Double {
        let stored = UserDefaults.standard.object(forKey: apparitionDelayKey) as? Double
        return stored ?? defaultApparitionDelayMs
    }

    /// Bindirim kapanırken opacity soluklaşarak mı kapansın, yoksa anında mı yok olsun.
    public static var fadeOutEnabled: Bool {
        UserDefaults.standard.object(forKey: fadeOutEnabledKey) as? Bool ?? defaultFadeOutEnabled
    }

    /// Kart küçük resimleri yüklenince belirme animasyonu (fade-in).
    public static var fadeInPreviewEnabled: Bool {
        UserDefaults.standard.object(forKey: fadeInPreviewEnabledKey) as? Bool ?? defaultFadeInPreviewEnabled
    }

    @MainActor
    public static func resetDefaults() {
        let d = UserDefaults.standard
        d.set(defaultModifier.rawValue, forKey: modifierKey)
        d.set(defaultTriggerKeyCode, forKey: triggerKeyCodeKey)
        d.set(defaultTriggerKeyLabel, forKey: triggerKeyLabelKey)
        d.set(defaultPreviewDuration, forKey: previewDurationKey)
        d.set(defaultApparitionDelayMs, forKey: apparitionDelayKey)
        d.set(defaultFadeOutEnabled, forKey: fadeOutEnabledKey)
        d.set(defaultFadeInPreviewEnabled, forKey: fadeInPreviewEnabledKey)
    }
}
