import SwiftUI
import GlassDoKit

/// Menü çubuğundaki bir ölçere tıklanınca açılan kart.
///
/// Menü çubuğu ögesi bir sayı gösterebiliyor; "peki neden bu kadar?"
/// sorusunun cevabı ana penceredeki kartta. O kartın kopyası değil,
/// kendisi açılıyor — panelde ve panoda kullanılan bileşenlerin aynısı.
struct MenuBarPopoverView: View {
    let category: MenuBarCategory

    private let controller = SystemStatsController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1.0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch category {
                case .processor:
                    ProcessorCard(cpu: controller.cpu, reduceMotion: reduceMotion)

                case .memory:
                    MemoryCard(
                        memory: controller.memory,
                        reduceMotion: reduceMotion,
                        animation: animation
                    )

                case .disk:
                    // Ana penceredeki disk sayfasının kullandığı görünümün
                    // aynısı: geçmiş grafiği yerine "en çok yer kaplayanlar"
                    // listesi. Disk doluluğu saatler içinde kıpırdamıyor —
                    // o grafiğin okunacak bir şeyi yoktu; yer açmak isteyen
                    // kullanıcının aradığı bilgi ise bu liste.
                    PanelDiskView(
                        disk: controller.disk,
                        reduceMotion: reduceMotion,
                        animation: animation,
                        allowsDeletion: false
                    )

                case .network:
                    NetworkCard(network: controller.network, reduceMotion: reduceMotion)
                    Divider().opacity(0.45).padding(.vertical, 14)
                    NetworkActivityCard(network: controller.network, reduceMotion: reduceMotion)

                case .battery:
                    BatteryCard(
                        battery: controller.battery,
                        reduceMotion: reduceMotion,
                        animation: animation
                    )
                    Divider().opacity(0.45).padding(.vertical, 14)
                    BatteryHealthCard(
                        battery: controller.battery,
                        reduceMotion: reduceMotion,
                        animation: animation
                    )

                case .device:
                    DeviceCard(device: controller.device, cpu: controller.cpu)
                }
            }
            // Kenar boşluğu, içindeki en büyük öğeye göre ölçülüyor: 40 pt'lik
            // baskın sayı 16 pt'lik bir kenarla kutunun duvarına yapışık
            // duruyordu.
            .padding(18)
        }
        // 340 pt, üç sütunlu lejantı ("32% • 7,56 GB" ×3) küçültmeden
        // sığdıramıyordu; 360 pt hem onu hem de rozet satırını rahatlatıyor.
        .frame(width: 360)
        .frame(maxHeight: 460)
        // Açıkken ölçüm dursa kart donardı; kapanınca abonelik bırakılıyor.
        .task { controller.start() }
        .onDisappear { controller.stop() }
    }
}

/// Makineyle ilgili, başka bir ölçere ait olmayan değerler.
struct DeviceCard: View {
    let device: DeviceStats
    let cpu: CPULoadStats

    var body: some View {
        StatCard(
            symbolName: "laptopcomputer",
            title: L10n.s("Makine", "Device", "Устройство")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                StatHeadline(
                    value: uptimeText,
                    detail: L10n.s(
                        "Son açılıştan beri",
                        "Since last boot",
                        "С момента загрузки"
                    ),
                    reduceMotion: true
                )

                StatColumns(
                    items: [
                        .init(
                            label: L10n.s("Çekirdek", "Cores", "Ядра"),
                            value: "\(cpu.coreCount)"
                        ),
                        .init(
                            label: L10n.s("Sıcaklık", "Temperature", "Температура"),
                            value: cpu.temperature.map { "\(Int($0.rounded()))°C" } ?? "—"
                        ),
                        .init(
                            label: L10n.s("Açılış", "Booted", "Загружен"),
                            value: bootText
                        ),
                    ],
                    reduceMotion: true
                )
            }
        }
    }

    private var uptimeText: String {
        let total = Int(device.uptime)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let dayUnit = L10n.s("g", "d", "д")
        let hourUnit = L10n.s("sa", "h", "ч")
        let minuteUnit = L10n.s("dk", "m", "м")

        if days > 0 { return "\(days)\(dayUnit) \(hours)\(hourUnit)" }
        if hours > 0 { return "\(hours)\(hourUnit) \(minutes)\(minuteUnit)" }
        return "\(minutes)\(minuteUnit)"
    }

    private var bootText: String {
        let boot = Date().addingTimeInterval(-device.uptime)
        return boot.formatted(date: .abbreviated, time: .shortened)
    }
}
