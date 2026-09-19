import Foundation
import GlassDoKit

/// Kenar çubuğunun seçebileceği her şey: bir görev listesi ya da "Sistem"
/// bölümündeki girdiler. `SmartList` yalnızca görev filtrelerini temsil
/// ettiği için sistem ekranlarını da içine katmak yerine ayrı bir üst tür
/// kullanılıyor.
enum SidebarSelection: Hashable {
    case list(SmartList)
    /// Ağ, batarya, disk ve işlemciyi toplayan kart panosu.
    case systemDashboard
    /// Bellek dökümü ve çalışan uygulama listesi.
    case systemMonitor
    /// Kenar rayındaki ölçer sayfalarının ana penceredeki karşılıkları.
    /// Panelde içerik açan her widget'ın burada da bir sayfası var; ray
    /// üzerindeki eylem ikonları (sabitle, pencere değiştirici, ekle,
    /// ayarlar) ise sayfa değil, bu yüzden burada yer almıyorlar.
    case network
    case battery
    case disk
    case processor
    /// Uygulamanın kendi dosya alanı.
    case folders
    /// Odak oturumları geçmişi.
    case focusHistory
}

// MARK: - Sayfa kimliği

import SwiftUI

/// Bir sayfanın kenar çubuğundaki ve araç çubuğundaki görünen kimliği.
struct SidebarEntry {
    let selection: SidebarSelection
    let title: String
    let symbolName: String
    let colors: [Color]
}

extension SidebarSelection {
    /// Başlık, simge ve renk tek yerden okunuyor: kenar çubuğu satırı ile
    /// pencere araç çubuğundaki sayfa rozeti aynı kaynağı paylaşmasa
    /// birbirinden kayardı.
    var entry: SidebarEntry {
        switch self {
        case .list(let list):
            SidebarEntry(
                selection: self,
                title: list.title,
                symbolName: list.symbolName,
                colors: list.tint
            )
        default:
            // Sistem girdileri tek bir listede tanımlı; oradan okunuyor.
            SidebarEntry.allSystemEntries.first { $0.selection == self }
                ?? SidebarEntry(
                    selection: self, title: "", symbolName: "square", colors: [.gray, .gray]
                )
        }
    }
}

extension SidebarEntry {
    /// Sistem bölümünün satırları. Sıra kasıtlı: önce bütünü gösteren
    /// pano, sonra tek tek ölçerler (bellek, ağ, batarya, disk, işlemci),
    /// sonra dosya alanı ve odak geçmişi.
    ///
    /// Renkler birbirinden ayrışıyor: kenar çubuğunda satırlar simgeden
    /// önce renkle tanınıyor, iki komşu satırın aynı tonu olması onları
    /// birbirine karıştırır.
    /// Kenar çubuğunda görünenler. Odak geçmişi şimdilik gizli: sayfa ve
    /// verisi yerinde duruyor, yalnızca satırı listede değil — geri açmak
    /// için `hiddenSelections`'dan çıkarmak yetiyor.
    static var systemEntries: [SidebarEntry] {
        allSystemEntries.filter { !hiddenSelections.contains($0.selection) }
    }

    /// Batarya kendi satırında değil: içeriği işlemci sayfasına taşındı
    /// (bkz. `ProcessorDashboardView`). Sayfa ve yönlendirmesi duruyor,
    /// yalnızca kenar çubuğunda ikinci bir kapı açmıyor.
    private static let hiddenSelections: Set<SidebarSelection> = [.focusHistory, .battery]

    static var allSystemEntries: [SidebarEntry] {
        [
            SidebarEntry(
                selection: .systemDashboard,
                title: L10n.systemOverviewTitle,
                symbolName: "gauge.with.dots.needle.67percent",
                colors: [Color(red: 0.36, green: 0.64, blue: 0.98), Color(red: 0.20, green: 0.44, blue: 0.88)]
            ),
            SidebarEntry(
                selection: .systemMonitor,
                title: L10n.systemMonitorTitle,
                symbolName: "memorychip",
                colors: [Color(red: 0.95, green: 0.42, blue: 0.34), Color(red: 0.82, green: 0.22, blue: 0.18)]
            ),
            SidebarEntry(
                selection: .network,
                title: L10n.networkActivityLabel,
                symbolName: "globe",
                colors: [Color(red: 0.24, green: 0.78, blue: 0.74), Color(red: 0.10, green: 0.56, blue: 0.56)]
            ),
            SidebarEntry(
                selection: .battery,
                title: L10n.batteryLabel,
                symbolName: "battery.100percent",
                colors: [Color(red: 0.36, green: 0.80, blue: 0.44), Color(red: 0.18, green: 0.62, blue: 0.30)]
            ),
            SidebarEntry(
                selection: .disk,
                title: L10n.diskLabel,
                symbolName: "internaldrive",
                colors: [Color(red: 1.0, green: 0.68, blue: 0.28), Color(red: 0.90, green: 0.46, blue: 0.12)]
            ),
            SidebarEntry(
                selection: .processor,
                title: L10n.processorBatteryTitle,
                symbolName: "cpu",
                colors: [Color(red: 0.64, green: 0.44, blue: 0.98), Color(red: 0.44, green: 0.24, blue: 0.86)]
            ),
            SidebarEntry(
                selection: .folders,
                title: L10n.shelfTitle,
                symbolName: "tray.full",
                colors: [Color(red: 0.56, green: 0.61, blue: 0.72), Color(red: 0.36, green: 0.41, blue: 0.52)]
            ),
            SidebarEntry(
                selection: .focusHistory,
                title: L10n.focusHistoryTitle,
                symbolName: "timer",
                colors: [Color(red: 0.98, green: 0.62, blue: 0.32), Color(red: 0.88, green: 0.40, blue: 0.14)]
            ),
        ]
    }
}
