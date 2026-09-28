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
    /// Toplam yükün geçmişi yerine o anki çekirdek başına yük — makinede
    /// kaç mantıksal çekirdek varsa o kadar ince çubuk, aynı anda hangi
    /// çekirdeğin çalıştığını gösteriyor.
    case cpuPerCoreBars
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
        case .cpuLoadBar, .cpuLoadPercent, .cpuLoadChart, .cpuPerCoreBars, .cpuTemperatureBar, .cpuTemperatureValue:
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
        case .cpuPerCoreBars:
            L10n.s("Çekirdekler", "Cores", "Ядра")
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

    /// Karonun altında yazan sunum adı — `title` ne ölçtüğünü söylüyor,
    /// bu nasıl gösterdiğini.
    ///
    /// Galeride aynı ölçümün üç sunumu yan yana duruyordu ve üçünün de
    /// altında aynı ad yazıyordu ("Toplam yük", "Toplam yük", "Toplam
    /// yük"). Hangisinin ne olduğunu yalnızca karonun içindeki küçük
    /// çizimden anlamak gerekiyordu.
    var styleTitle: String {
        switch self {
        case .cpuLoadBar, .cpuTemperatureBar, .memoryUsedBar, .diskUsedBar, .batteryLevelBar:
            L10n.s("Çubuk", "Bar", "Шкала")
        case .cpuLoadPercent, .memoryUsedPercent, .diskUsedPercent, .batteryPercent,
             .batteryHealthPercent:
            L10n.s("Yüzde", "Percent", "Проценты")
        case .cpuLoadChart, .memoryPressureChart, .networkActivity:
            L10n.s("Grafik", "Graph", "График")
        case .cpuPerCoreBars:
            L10n.s("Çubuklar", "Bars", "Шкалы")
        case .cpuTemperatureValue:
            L10n.s("Derece", "Degrees", "Градусы")
        case .memoryUsedBytes, .memorySwapBytes, .diskUsedBytes, .diskFreeBytes,
             .networkDataToday:
            L10n.s("Bayt", "Bytes", "Байты")
        case .diskUsedRing:
            L10n.s("Halka", "Ring", "Кольцо")
        case .networkDownload, .networkUpload:
            L10n.s("Hız", "Speed", "Скорость")
        case .networkArrows:
            L10n.s("Oklar", "Arrows", "Стрелки")
        case .networkVPN:
            L10n.s("Rozet", "Badge", "Значок")
        case .batteryPower:
            L10n.s("Watt", "Watts", "Ватты")
        case .batteryCycles:
            L10n.s("Sayı", "Count", "Число")
        case .batteryTimeRemaining, .deviceUptime:
            L10n.s("Süre", "Time", "Время")
        }
    }

    static func items(in category: MenuBarCategory) -> [MenuBarItemKind] {
        allCases.filter { $0.category == category }
    }

    /// Bir kategorinin ölçümleri, her biri kendi sunumlarıyla.
    ///
    /// Galeri eskiden kategorinin bütün karolarını tek bir üç sütunlu
    /// ızgaraya diziyordu; aynı ölçümün sunumları ızgara akışında
    /// birbirinden kopuyor, satır sonunda bölünebiliyordu. Gruplanınca
    /// "şunu şu biçimde göster" seçimi göz önünde duruyor.
    static func readings(in category: MenuBarCategory) -> [MenuBarReading] {
        var order: [String] = []
        var groups: [String: [MenuBarItemKind]] = [:]
        for kind in items(in: category) {
            if groups[kind.title] == nil { order.append(kind.title) }
            groups[kind.title, default: []].append(kind)
        }
        return order.compactMap { title in
            guard let kinds = groups[title], let first = kinds.first else { return nil }
            return MenuBarReading(id: first.rawValue, title: title, kinds: kinds)
        }
    }
}

/// Tek bir ölçüm ve onu gösterme biçimleri.
struct MenuBarReading: Identifiable, Sendable {
    let id: String
    let title: String
    let kinds: [MenuBarItemKind]
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
