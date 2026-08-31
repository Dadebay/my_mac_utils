import Foundation
import CoreGraphics

public enum PanelSettings {
    public static let iconScaleKey = "panel.iconScale"
    public static let panelWidthKey = "panel.width"
    public static let panelHeightKey = "panel.height"
    public static let railWidthKey = "panel.railWidth"
    public static let cornerRadiusKey = "panel.cornerRadius"
    public static let selectedIconCornerRadiusKey = "panel.selectedIconCornerRadius"
    /// Seçili/üzerine gelinen ikonun arkasındaki vurgu şekli, ikonun tıklama
    /// hedefinin tamamını dolduruyordu — bu, arka planı kenarlardan içeri
    /// çeken boşluk.
    public static let selectedIconPaddingKey = "panel.selectedIconPadding"

    public static let showTasksIconKey = "panel.icon.tasks"
    public static let showAddIconKey = "panel.icon.add"
    public static let showCompletedIconKey = "panel.icon.completed"
    public static let showFoldersIconKey = "panel.icon.folders"
    public static let showMemoryIconKey = "panel.icon.memory"
    public static let showNetworkIconKey = "panel.icon.network"
    public static let showBatteryIconKey = "panel.icon.battery"
    public static let showDiskIconKey = "panel.icon.disk"
    public static let showProcessorIconKey = "panel.icon.processor"
    public static let showPinIconKey = "panel.icon.pin"
    public static let showSettingsIconKey = "panel.icon.settings"
    public static let showWindowSwitcherIconKey = "panel.icon.windowSwitcher"

    /// Ayarlardaki "görünür ikon" sayacının paydası — yeni bir ikon
    /// eklendiğinde tek yerden güncellensin.
    public static let totalIconCount = 12

    public static let iconScaleRange: ClosedRange<Double> = 0.8...1.3
    public static let panelWidthRange: ClosedRange<Double> = 260...420
    public static let panelHeightRange: ClosedRange<Double> = 280...600
    public static let railWidthRange: ClosedRange<Double> = 40...72
    public static let cornerRadiusRange: ClosedRange<Double> = 0...32
    public static let selectedIconCornerRadiusRange: ClosedRange<Double> = 0...16
    /// Üst sınır, hit hedefinin (en az 34 pt) tamamen boşalmasını önlüyor.
    public static let selectedIconPaddingRange: ClosedRange<Double> = 0...10

    // MARK: - Varsayılanlar (sıfırlama için)

    public static let defaultIconScale: Double = 0.87
    public static let defaultRailWidth = Double(EdgeTokens.railWidth)
    public static let defaultPanelWidth = Double(EdgeTokens.panelWidth)
    public static let defaultPanelHeight = Double(EdgeTokens.panelHeight)
    public static let defaultCornerRadius: Double = 13
    public static let defaultSelectedIconCornerRadius: Double = 10
    public static let defaultSelectedIconPadding: Double = 4

    @MainActor
    public static func resetSizeDefaults() {
        let d = UserDefaults.standard
        d.set(defaultIconScale, forKey: iconScaleKey)
        d.set(defaultRailWidth, forKey: railWidthKey)
        d.set(defaultPanelWidth, forKey: panelWidthKey)
        d.set(defaultPanelHeight, forKey: panelHeightKey)
        d.set(defaultCornerRadius, forKey: cornerRadiusKey)
        d.set(defaultSelectedIconPadding, forKey: selectedIconPaddingKey)
    }

    @MainActor
    public static func resetIconDefaults() {
        let d = UserDefaults.standard
        for key in [showTasksIconKey, showAddIconKey, showCompletedIconKey,
                    showFoldersIconKey, showMemoryIconKey, showPinIconKey,
                    showSettingsIconKey, showWindowSwitcherIconKey] {
            d.set(true, forKey: key)
        }
        // Sistem ölçerleri isteğe bağlı: ray zaten sekiz ikonla dolu, dördünü
        // birden eklemek mevcut yerleşimi habersizce bozardı.
        for key in [showNetworkIconKey, showBatteryIconKey,
                    showDiskIconKey, showProcessorIconKey] {
            d.set(false, forKey: key)
        }
        d.set(defaultSelectedIconCornerRadius, forKey: selectedIconCornerRadiusKey)
    }

    public static var iconScale: Double {
        let stored = UserDefaults.standard.double(forKey: iconScaleKey)
        return stored == 0 ? 1.0 : stored
    }

    public static var railWidth: CGFloat {
        let stored = UserDefaults.standard.double(forKey: railWidthKey)
        return CGFloat(stored == 0 ? Double(EdgeTokens.railWidth) : stored)
    }

    public static var panelWidth: CGFloat {
        let stored = UserDefaults.standard.double(forKey: panelWidthKey)
        return CGFloat(stored == 0 ? Double(EdgeTokens.panelWidth) : stored)
    }

    public static var panelHeight: CGFloat {
        let stored = UserDefaults.standard.double(forKey: panelHeightKey)
        return CGFloat(stored == 0 ? Double(EdgeTokens.panelHeight) : stored)
    }

    public static var cornerRadius: CGFloat {
        let raw = UserDefaults.standard.object(forKey: cornerRadiusKey) as? Double
        return CGFloat(raw ?? defaultCornerRadius)
    }

    private static func flag(_ key: String, default fallback: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    public static var showTasksIcon: Bool { flag(showTasksIconKey) }
    public static var showAddIcon: Bool { flag(showAddIconKey) }
    public static var showCompletedIcon: Bool { flag(showCompletedIconKey) }
    public static var showFoldersIcon: Bool { flag(showFoldersIconKey) }
    public static var showMemoryIcon: Bool { flag(showMemoryIconKey) }
    public static var showPinIcon: Bool { flag(showPinIconKey) }
    public static var showSettingsIcon: Bool { flag(showSettingsIconKey) }
    public static var showWindowSwitcherIcon: Bool { flag(showWindowSwitcherIconKey) }

    // Sistem ölçerleri varsayılan olarak kapalı — kullanıcı Ayarlar'dan açar.
    public static var showNetworkIcon: Bool { flag(showNetworkIconKey, default: false) }
    public static var showBatteryIcon: Bool { flag(showBatteryIconKey, default: false) }
    public static var showDiskIcon: Bool { flag(showDiskIconKey, default: false) }
    public static var showProcessorIcon: Bool { flag(showProcessorIconKey, default: false) }

    public static var visibleIconCount: Int {
        [showTasksIcon, showAddIcon, showCompletedIcon, showFoldersIcon,
         showMemoryIcon, showNetworkIcon, showBatteryIcon, showDiskIcon,
         showProcessorIcon, showPinIcon, showSettingsIcon, showWindowSwitcherIcon]
            .filter { $0 }.count
    }

    /// Gerçek zamanlı ray yüksekliği — gizlenen ikonlar varsa küçülür.
    public static var railHeight: CGFloat {
        16 + (CGFloat(max(visibleIconCount, 1)) * EdgeTokens.railRowHeight) + 16
    }

    /// Açık panel raydan kısa olamaz. Aksi hâlde çok sayıda ikon görünürken
    /// SwiftUI rayı daha kısa pencereye sığdırmaya çalışır ve ikonlar
    /// küçülmüş/kırpılmış gibi görünür.
    public static var effectivePanelHeight: CGFloat {
        max(panelHeight, railHeight)
    }
}
