import Foundation
import AppKit
import SwiftUI
import GlassDoKit

// MARK: - Sınıflandırma

/// Hatanın hangi bölümde görüldüğü. Kullanıcı bunu seçiyor, çünkü
/// "uygulama çöktü" tek başına hangi kodun suçlu olduğunu söylemiyor —
/// bölüm bilgisi raporu doğrudan ilgili dosya kümesine bağlıyor
/// (bkz. `docs/16-BUG-REPORTS.md`).
enum BugArea: String, CaseIterable, Identifiable, Sendable {
    case panel
    case tasks
    case notes
    case windowSwitcher
    case systemMetrics
    case widgets
    case clipboard
    case storage
    case purchases
    case settings
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .panel: L10n.s("Kenar Paneli / Ray", "Edge Panel / Rail", "Боковая панель")
        case .tasks: L10n.s("Görevler", "Tasks", "Задачи")
        case .notes: L10n.s("Notlar", "Notes", "Заметки")
        case .windowSwitcher: L10n.s("Pencere Değiştirici", "Window Switcher", "Переключатель окон")
        case .systemMetrics: L10n.s("Sistem Ölçerleri", "System Metrics", "Системные метрики")
        case .widgets: L10n.s("Widget'lar", "Widgets", "Виджеты")
        case .clipboard: L10n.s("Pano", "Clipboard", "Буфер обмена")
        case .storage: L10n.s("Dosyalar / Klasörler", "Files / Folders", "Файлы и папки")
        case .purchases: L10n.s("Satın Alma / Pro", "Purchases / Pro", "Покупки / Pro")
        case .settings: L10n.s("Ayarlar", "Settings", "Настройки")
        case .other: L10n.s("Diğer", "Other", "Другое")
        }
    }

    /// Raporu okurken ilk bakılacak yer. Firestore belgesine de yazılıyor:
    /// yönetim panelinde raporu açan kişi dosya ağacını ezbere bilmek
    /// zorunda kalmıyor.
    var sourceHint: String {
        switch self {
        case .panel: "Sources/macOS/Panel"
        case .tasks: "Sources/macOS/MainWindow, Sources/GlassDoKit/Store"
        case .notes: "Sources/macOS/Notes"
        case .windowSwitcher: "Sources/macOS/WindowSwitcher"
        case .systemMetrics: "Sources/Shared, Sources/macOS/MainWindow/SystemMetricPage.swift"
        case .widgets: "Sources/Widgets"
        case .clipboard: "Sources/macOS/Panel/PanelClipboardView.swift"
        case .storage: "Sources/macOS/Storage"
        case .purchases: "Sources/macOS/Purchases"
        case .settings: "Sources/macOS/Settings"
        case .other: "-"
        }
    }
}

/// Ne kadar engelleyici. Öncelik sıralaması yönetim tarafında bu alana
/// göre yapılıyor; kullanıcıya "önemli mi" diye sormak, serbest metinden
/// aciliyeti tahmin etmeye çalışmaktan daha güvenilir.
enum BugSeverity: String, CaseIterable, Identifiable, Sendable {
    case crash
    case blocking
    case annoying
    case cosmetic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crash: L10n.s("Çöküyor", "Crashes", "Вылетает")
        case .blocking: L10n.s("Kullanamıyorum", "Can't use it", "Не могу пользоваться")
        case .annoying: L10n.s("Rahatsız edici", "Annoying", "Мешает")
        case .cosmetic: L10n.s("Görsel kusur", "Cosmetic", "Косметика")
        }
    }

    /// Açılır menüdeki satırın önündeki nokta. Aciliyeti tek bakışta
    /// anlatıyor — dört düz metin satırı arasında "çöküyor" ile "görsel
    /// kusur" aynı ağırlıkta görünüyordu.
    var tint: Color {
        switch self {
        case .crash: .red
        case .blocking: .orange
        case .annoying: .yellow
        case .cosmetic: .secondary
        }
    }

}

// MARK: - Tanılama

/// Rapora eklenen teknik bağlam. Kullanıcının yazdığı metinden ayrı
/// tutuluyor: kullanıcı "widget açılmıyor" der, hangi macOS sürümünde,
/// hangi panel kenarında, sandbox'lı yapıda mı — bunları yazmaz. Bu
/// alanların çoğu daha önce çözülen hataların gerçek ayırt edici
/// noktalarıydı (sandbox'ta çalışmayan pencere kapatma gibi).
///
/// Hiçbir görev başlığı, dosya adı, pano içeriği ya da kişisel veri
/// toplanmıyor — yalnızca sayaçlar, sürümler ve ayar durumları.
struct BugDiagnostics: Sendable {
    var appVersion: String
    var appBuild: String
    var isSandboxed: Bool
    var isPro: Bool
    var osVersion: String
    var deviceModel: String
    var architecture: String
    var cpuCores: Int
    var memoryGB: Double
    var locale: String
    var language: String
    var region: String
    var screens: [String]
    var panelMode: String
    var panelEdge: String
    var panelVisible: Bool
    var analyticsConsent: Bool
    var systemUptimeHours: Double
    var usageToday: [String: Int]

    @MainActor
    static func collect(panel: EdgePanelController) async -> BugDiagnostics {
        let info = Bundle.main.infoDictionary
        return BugDiagnostics(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: info?["CFBundleVersion"] as? String ?? "unknown",
            isSandboxed: ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil,
            isPro: ProStore.shared.isPro,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: Self.sysctlString("hw.model"),
            architecture: Self.sysctlString("hw.machine"),
            cpuCores: ProcessInfo.processInfo.processorCount,
            memoryGB: (Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 * 10).rounded() / 10,
            locale: Locale.current.identifier,
            language: Locale.current.language.languageCode?.identifier ?? "unknown",
            region: Locale.current.region?.identifier ?? "unknown",
            screens: NSScreen.screens.map { screen in
                let size = screen.frame.size
                return "\(Int(size.width))x\(Int(size.height))@\(screen.backingScaleFactor)"
            },
            panelMode: panel.mode.rawValue,
            panelEdge: panel.edge.rawValue,
            panelVisible: panel.isPanelVisible,
            analyticsConsent: AnalyticsConsent.isGranted,
            systemUptimeHours: (ProcessInfo.processInfo.systemUptime / 3600 * 10).rounded() / 10,
            // "Bugün ne yaptı" sorusunun cevabı: hatanın hangi akışın
            // içinde ortaya çıktığını daraltıyor. Yalnızca özellik adı ve
            // sayı — içerik yok.
            usageToday: await UsageStore.shared.todayFeatureCounts()
        )
    }

    /// Firestore'a yazılacak biçim. Düz bir sözlük yerine iç içe gruplar:
    /// yönetim panelinde uygulama / sistem / durum bilgisini ayrı ayrı
    /// göstermek, otuz alanı tek listede taramaktan kolay.
    var firestoreFields: [String: Any] {
        [
            "app": [
                "version": appVersion,
                "build": appBuild,
                "sandboxed": isSandboxed,
                "isPro": isPro,
            ],
            "system": [
                "osVersion": osVersion,
                "deviceModel": deviceModel,
                "architecture": architecture,
                "cpuCores": cpuCores,
                "memoryGB": memoryGB,
                "locale": locale,
                "language": language,
                "region": region,
                "screens": screens,
                "uptimeHours": systemUptimeHours,
            ],
            "state": [
                "panelMode": panelMode,
                "panelEdge": panelEdge,
                "panelVisible": panelVisible,
                "analyticsConsent": analyticsConsent,
            ],
            "usageToday": usageToday,
        ]
    }

    /// Gönder düğmesinin altındaki "neler gidiyor" listesi. Kullanıcıya
    /// gönderilecek veriyi birebir göstermek, onay istemenin en dürüst
    /// biçimi — soyut bir "teknik bilgi" ifadesi neyi kabul ettiğini
    /// söylemiyor.
    var humanReadableSummary: [String] {
        [
            "GlassDo \(appVersion) (\(appBuild))\(isSandboxed ? " · sandbox" : "")\(isPro ? " · Pro" : "")",
            "\(osVersion) · \(deviceModel) · \(architecture)",
            "\(cpuCores) \(L10n.s("çekirdek", "cores", "ядер")) · \(String(format: "%.1f", memoryGB)) GB · \(screens.joined(separator: ", "))",
            "\(locale) · \(region)",
            "panel: \(panelMode) · \(panelEdge) · \(panelVisible ? L10n.s("açık", "visible", "показана") : L10n.s("kapalı", "hidden", "скрыта"))",
            usageToday.isEmpty
                ? L10n.s("bugün kayıtlı kullanım yok", "no usage recorded today", "за сегодня нет данных")
                : usageToday.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key)×\($0.value)" }.joined(separator: " · "),
        ]
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var raw = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &raw, &size, nil, 0)
        return String(cString: raw)
    }
}
