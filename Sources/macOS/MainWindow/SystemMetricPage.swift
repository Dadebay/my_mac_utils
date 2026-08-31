import GlassDoKit
import SwiftUI

/// Kenar panelindeki ölçer sayfalarının ana penceredeki karşılığı.
///
/// İçerik bileşenleri panelinkiyle **aynı** (`PanelNetworkView`,
/// `PanelBatteryView`, `PanelDiskView`, `PanelProcessorView`) ve ölçüm aynı
/// paylaşılan denetleyiciden geliyor: iki yüzey için iki ayrı görünüm ve iki
/// ayrı döngü tutulsaydı zamanla birbirinden kayarlardı.
///
/// Tek fark ölçü. Panel 329 pt'ye sabitken bu sayfa pencereyle birlikte
/// büyüyor, ama okunur bir genişlikte duruyor — geniş pencerede satırların
/// sayfanın karşı ucuna uzaması okumayı zorlaştırır.
struct SystemMetricPage: View {
    let metric: PanelSystemStatView.Metric

    private let controller = SystemStatsController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Grafiklerin ve sayıların yerine oturma hareketi: kritik sönümlü,
    /// taşmasız. İki saniyede bir gelen veri dikkat çekmeden değişmeli.
    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1.0)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch metric {
                case .network:
                    section {
                        PanelNetworkView(
                            network: controller.network,
                            reduceMotion: reduceMotion,
                            animation: animation
                        )
                    }
                    section {
                        PanelNetworkProcessList(reduceMotion: reduceMotion)
                    }
                    section(isLast: true) {
                        SpeedTestSection()
                    }

                case .battery:
                    section(isLast: true) {
                        PanelBatteryView(
                            battery: controller.battery,
                            reduceMotion: reduceMotion,
                            animation: animation
                        )
                    }

                case .disk:
                    section(isLast: true) {
                        PanelDiskView(
                            disk: controller.disk,
                            reduceMotion: reduceMotion,
                            animation: animation
                        )
                    }

                case .processor:
                    section(isLast: true) {
                        PanelProcessorView(
                            cpu: controller.cpu,
                            memory: controller.memory,
                            reduceMotion: reduceMotion,
                            animation: animation
                        )
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 6)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        // Ölçüm aboneliği sayfayla birlikte açılıp kapanıyor; denetleyici
        // sayaçlı olduğu için panel de açıksa ikinci bir döngü kurulmuyor.
        .task { controller.start() }
        .onDisappear { controller.stop() }
    }

    private var title: String {
        switch metric {
        case .network: L10n.networkActivityLabel
        case .battery: L10n.batteryLabel
        case .disk: L10n.diskLabel
        case .processor: L10n.processorLoadLabel
        }
    }

    /// Alt başlık sayfanın "hangi donanım" sorusunu yanıtlıyor: hangi arayüz,
    /// hangi birim, kaç çekirdek. Değerler ölçümden geliyor, metin değil.
    private var subtitle: String {
        switch metric {
        case .network:
            controller.network.interfaceName
        case .battery:
            controller.battery.isPresent ? "\(controller.battery.chargePercent)%" : ""
        case .disk:
            controller.disk.volumeName
        case .processor:
            L10n.processorCoreSummary(controller.cpu.coreCount)
        }
    }

    /// Panodaki kart ritmiyle aynı: kartlar arasında çerçeve değil ayraç —
    /// kutu içinde kutu görüntüsü oluşmasın.
    private func section<Content: View>(
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(.vertical, 18)

            if !isLast {
                Divider().opacity(0.45)
            }
        }
    }
}
