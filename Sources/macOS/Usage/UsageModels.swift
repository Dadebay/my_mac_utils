import SwiftUI
import GlassDoKit

/// Kullanıcının bilinçli olarak tetiklediği, sayılabilir eylemler.
///
/// Bu liste kasıtlı olarak dar: yalnızca kenar rayında, ana penceredeki
/// kenar çubuğunda veya menü çubuğunda gerçek bir tıklamayla ulaşılabilen
/// eylemler var. Görev başlığı, dosya adı veya benzeri hiçbir içerik burada
/// tutulmuyor — yalnızca "hangi özellik" ve "ne zaman".
enum UsageFeature: String, Codable, CaseIterable, Sendable {
    case tasks, quickAdd, completed, folders, memory, network, battery, disk, processor
    case windowSwitcher, panelVisibility, pinMode

    /// Usage panelindeki "widget listesi" yalnızca bunları gösterir —
    /// diğerleri toplam/"en çok kullanılan" hesabına girer ama satır
    /// olarak listelenmez (spec'in "öncelikli widget kullanım listesi").
    var isWidget: Bool {
        switch self {
        case .tasks, .completed, .folders, .memory, .network, .battery, .disk, .processor: true
        case .quickAdd, .windowSwitcher, .panelVisibility, .pinMode: false
        }
    }

    var title: String {
        switch self {
        case .tasks: L10n.activeTasks
        case .quickAdd: L10n.s("Hızlı Ekle", "Quick Add", "Быстрое добавление")
        case .completed: L10n.completedTasks
        case .folders: L10n.folders
        case .memory: L10n.s("Bellek", "Memory", "Память")
        case .network: L10n.s("Ağ", "Network", "Сеть")
        case .battery: L10n.s("Batarya", "Battery", "Батарея")
        case .disk: L10n.s("Disk", "Disk", "Диск")
        case .processor: L10n.s("İşlemci", "Processor", "Процессор")
        case .windowSwitcher: L10n.s("Pencere Değiştirici", "Window Switcher", "Переключатель окон")
        case .panelVisibility: L10n.s("Panel Görünürlüğü", "Panel Visibility", "Видимость панели")
        case .pinMode: L10n.s("Sabitleme", "Pin Mode", "Закрепление")
        }
    }

    var symbolName: String {
        switch self {
        case .tasks: "checklist"
        case .quickAdd: "plus"
        case .completed: "checkmark.circle"
        case .folders: "folder"
        case .memory: "memorychip"
        case .network: "globe"
        case .battery: "battery.100percent"
        case .disk: "internaldrive"
        case .processor: "cpu"
        case .windowSwitcher: "rectangle.on.rectangle"
        case .panelVisibility: "eye"
        case .pinMode: "pin"
        }
    }

    /// Sidebar/rail'de aynı özellik için zaten kullanılan renkler — yeni,
    /// tutarsız bir palet icat etmemek için buradan aynen alınıyor.
    var tint: Color {
        switch self {
        case .tasks: Color(red: 0.24, green: 0.58, blue: 1.0)
        case .quickAdd: .accentColor
        case .completed: Color(red: 0.30, green: 0.78, blue: 0.45)
        case .folders: Color(red: 0.56, green: 0.61, blue: 0.72)
        case .memory: Color(red: 0.95, green: 0.42, blue: 0.34)
        case .network: Color(red: 0.24, green: 0.78, blue: 0.74)
        case .battery: Color(red: 0.36, green: 0.80, blue: 0.44)
        case .disk: Color(red: 1.0, green: 0.68, blue: 0.28)
        case .processor: Color(red: 0.64, green: 0.44, blue: 0.98)
        case .windowSwitcher: Color(red: 1.0, green: 0.62, blue: 0.24)
        case .panelVisibility: Color(white: 0.62)
        case .pinMode: Color(white: 0.62)
        }
    }
}

/// Bir kaydın hangi yüzeyden geldiği. Yalnızca dahili/teşhis amaçlı —
/// hiçbir arayüz şu an kaynağa göre kırılım göstermiyor.
enum UsageSource: String, Codable, Sendable {
    case edgeRail, mainWindow, menuBar, keyboardShortcut
}

/// Kullanım panelindeki dönem seçici.
enum UsagePeriod: String, CaseIterable, Sendable, Identifiable {
    case last7Days, last30Days, lastYear, allTime
    var id: String { rawValue }

    var title: String {
        switch self {
        case .last7Days: L10n.s("Son 7 Gün", "Last 7 Days", "7 дней")
        case .last30Days: L10n.s("Son 30 Gün", "Last 30 Days", "30 дней")
        case .lastYear: L10n.s("Son Yıl", "Last Year", "Год")
        case .allTime: L10n.s("Tüm Zamanlar", "All Time", "Всё время")
        }
    }

    /// Bugün dahil, geriye kaç takvim günü. `nil` = sınırsız (all-time).
    var dayWindow: Int? {
        switch self {
        case .last7Days: 7
        case .last30Days: 30
        case .lastYear: 365
        case .allTime: nil
        }
    }
}

/// Tek bir günün, o gün içindeki her özellik için sayacı.
struct DailyUsageBucket: Codable, Sendable, Equatable {
    var counts: [String: Int] = [:]

    subscript(_ feature: UsageFeature) -> Int {
        get { counts[feature.rawValue] ?? 0 }
        set { counts[feature.rawValue] = newValue }
    }

    var total: Int { counts.values.reduce(0, +) }
}

/// Seçilen dönemde tek bir özelliğin özeti.
struct FeatureUsage: Identifiable, Sendable {
    let feature: UsageFeature
    let count: Int
    /// Dönemdeki tüm widget kullanımına oranı (0...1) — yalnızca
    /// `isWidget` özellikler arasında hesaplanıyor.
    let fraction: Double
    var id: UsageFeature { feature }
}

/// Küçük 7 günlük grafiğin tek bir çubuğu.
struct DayCount: Identifiable, Sendable {
    let day: Date
    let total: Int
    var id: Date { day }
}

/// `UsageStore.snapshot(for:)`'un döndürdüğü, görünümün doğrudan
/// çizebileceği hazır sonuç.
struct UsageSnapshot: Sendable {
    let period: UsagePeriod
    let totalUses: Int
    let mostUsed: UsageFeature?
    /// Dönem içinde en az bir kullanım olan gün sayısı.
    let activeDays: Int
    /// Yalnızca `isWidget` özellikler, en çok kullanılan başta, sıfır
    /// kullanımı olanlar dışarıda. Eşitlikte `UsageFeature.allCases`
    /// sırası bozan deterministic bir ikincil anahtar.
    let features: [FeatureUsage]
    /// Son 7 günün toplamları, en eskisi başta.
    let dailyTotals: [DayCount]
    let lastUsedFeature: UsageFeature?
    let lastUsedDate: Date?

    var isEmpty: Bool { totalUses == 0 }

    static let empty = UsageSnapshot(
        period: .allTime, totalUses: 0, mostUsed: nil, activeDays: 0,
        features: [], dailyTotals: [], lastUsedFeature: nil, lastUsedDate: nil
    )
}
