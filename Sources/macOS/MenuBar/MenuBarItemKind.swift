import Foundation
import GlassDoKit

/// Menü çubuğu ölçerlerinin grupları. Ayarlardaki galeri bu başlıklar
/// altında diziliyor — kullanıcı "batarya" diye arar, "yüzde" diye değil.
enum MenuBarCategory: String, CaseIterable, Identifiable, Sendable {
    case processor, memory, disk, network, battery, device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processor: L10n.s("İşlemci", "Processor", "Процессор")
        case .memory: L10n.memoryLabel
        case .disk: L10n.diskLabel
        case .network: L10n.s("Ağ", "Network", "Сеть")
        case .battery: L10n.batteryLabel
        case .device: L10n.s("Makine", "Device", "Устройство")
        }
    }

    var symbolName: String {
        switch self {
        case .processor: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "globe"
        case .battery: "battery.100percent"
        case .device: "laptopcomputer"
        }
    }
}

/// Menü çubuğuna tek tek eklenebilen ölçerler.
///
/// Aynı ölçüm birkaç biçimde sunuluyor (çubuk, yüzde, bayt): menü çubuğu
/// dar bir yer ve herkesin önceliği farklı — biri diskin yüzdesini,
/// bir diğeri kalan gigabaytı okumak istiyor. Seçim kullanıcının.
///
/// `rawValue`'lar kalıcı: ayarlarda saklanıyorlar, değiştirilirlerse
/// kullanıcının seçimi kaybolur.
enum MenuBarItemKind: String, CaseIterable, Identifiable, Sendable {
    // İşlemci
    case cpuLoadBar
    case cpuLoadPercent
    case cpuLoadChart
    case cpuTemperatureBar
    case cpuTemperatureValue

    // Bellek
    case memoryUsedBar
    case memoryUsedBytes
    case memoryUsedPercent
    case memorySwapBytes
    case memoryPressureChart

    // Disk
    case diskUsedBar
    case diskUsedRing
    case diskUsedBytes
    case diskUsedPercent
    case diskFreeBytes

    // Ağ
    case networkActivity
    case networkDownload
    case networkUpload
    case networkArrows
    case networkVPN
    case networkDataToday

    // Batarya
    case batteryLevelBar
    case batteryPercent
    case batteryPower
    case batteryCycles
    case batteryHealthPercent
    case batteryTimeRemaining

    // Makine
    case deviceUptime

    var id: String { rawValue }

    var category: MenuBarCategory {
        switch self {
        case .cpuLoadBar, .cpuLoadPercent, .cpuLoadChart, .cpuTemperatureBar, .cpuTemperatureValue:
            .processor
        case .memoryUsedBar, .memoryUsedBytes, .memoryUsedPercent, .memorySwapBytes, .memoryPressureChart:
            .memory
        case .diskUsedBar, .diskUsedRing, .diskUsedBytes, .diskUsedPercent, .diskFreeBytes:
            .disk
        case .networkActivity, .networkDownload, .networkUpload, .networkArrows, .networkVPN, .networkDataToday:
            .network
        case .batteryLevelBar, .batteryPercent, .batteryPower, .batteryCycles, .batteryHealthPercent, .batteryTimeRemaining:
            .battery
        case .deviceUptime:
            .device
        }
    }

    /// Galerideki karonun altında yazan ad — ne ölçtüğünü söyler,
    /// nasıl gösterdiğini değil (aynı ada sahip iki karo yan yana durur,
    /// biri çubuk biri sayıdır).
    var title: String {
        switch self {
        case .cpuLoadBar, .cpuLoadPercent, .cpuLoadChart:
            L10n.s("Toplam yük", "Total Load", "Общая загрузка")
        case .cpuTemperatureBar, .cpuTemperatureValue:
            L10n.s("Sıcaklık", "Temperature", "Температура")
        case .memoryUsedBar, .memoryUsedBytes, .memoryUsedPercent:
            L10n.s("Kullanılan", "Used", "Использовано")
        case .memorySwapBytes:
            L10n.s("Takas", "Swap Used", "Подкачка")
        case .memoryPressureChart:
            L10n.s("Baskı", "Pressure", "Нагрузка")
        case .diskUsedBar, .diskUsedRing, .diskUsedBytes, .diskUsedPercent:
            L10n.s("Kullanılan", "Used", "Использовано")
        case .diskFreeBytes:
            L10n.s("Boş", "Free", "Свободно")
        case .networkActivity, .networkArrows:
            L10n.s("Etkinlik", "Activity", "Активность")
        case .networkDownload:
            L10n.s("İndirme", "Download", "Загрузка")
        case .networkUpload:
            L10n.s("Yükleme", "Upload", "Отдача")
        case .networkVPN:
            "VPN"
        case .networkDataToday:
            L10n.s("Bugünkü veri", "Data Today", "Трафик за сегодня")
        case .batteryLevelBar, .batteryPercent:
            L10n.s("Şarj düzeyi", "Charge Level", "Уровень заряда")
        case .batteryPower:
            L10n.s("Güç", "Power", "Мощность")
        case .batteryCycles:
            L10n.s("Döngü", "Cycles", "Циклы")
        case .batteryHealthPercent:
            L10n.s("Sağlık", "Health", "Здоровье")
        case .batteryTimeRemaining:
            L10n.s("Kalan süre", "Time Left", "Осталось")
        case .deviceUptime:
            L10n.s("Çalışma süresi", "Up time", "Время работы")
        }
    }

    static func items(in category: MenuBarCategory) -> [MenuBarItemKind] {
        allCases.filter { $0.category == category }
    }
}

/// Menü çubuğunda hangi ölçerlerin göründüğü.
///
/// Sıra da kalıcı: kullanıcı üç ölçer seçtiyse menü çubuğunda hep aynı
/// sırada dursunlar, her açılışta yer değiştirmesinler.
enum MenuBarSettings {
    static let enabledItemsKey = "menubar.enabledItems"

    /// Kurulumdan sonra menü çubuğu boş görünmesin diye iki ölçer açık
    /// geliyor; ikisi de bir satırlık ve dar.
    static let defaultItems: [MenuBarItemKind] = [.cpuLoadPercent, .memoryUsedPercent]

    static var enabledItems: [MenuBarItemKind] {
        get {
            guard let raw = UserDefaults.standard.string(forKey: enabledItemsKey) else {
                return defaultItems
            }
            // Boş dize "hiçbiri" demek; varsayılana dönmemeli.
            guard !raw.isEmpty else { return [] }
            return raw.split(separator: ",").compactMap { MenuBarItemKind(rawValue: String($0)) }
        }
        set {
            UserDefaults.standard.set(
                newValue.map(\.rawValue).joined(separator: ","),
                forKey: enabledItemsKey
            )
        }
    }

    static func isEnabled(_ kind: MenuBarItemKind) -> Bool {
        enabledItems.contains(kind)
    }

    /// Açıksa kapatır, kapalıysa listenin sonuna ekler.
    static func toggle(_ kind: MenuBarItemKind) {
        var items = enabledItems
        if let index = items.firstIndex(of: kind) {
            items.remove(at: index)
        } else {
            items.append(kind)
        }
        enabledItems = items
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: enabledItemsKey)
    }
}
