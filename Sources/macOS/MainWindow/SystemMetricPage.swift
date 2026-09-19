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
        reduceMotion ? nil : Motion.dataUpdate
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
                            animation: animation,
                            isWide: true
                        )
                    }
                    // Süreç listesi ile hız testi yan yana: ikisi de kısa,
                    // alt alta dizilince sayfanın yarısı boş kalıyordu.
                    section(isLast: true) {
                        // Eşik 820: hız testi artık kadran + açıklama
                        // sütunundan oluşuyor, tek başına ~420 pt istiyor.
                        // Daha dar bir eşikte iki sütun yan yana sıkışıp
                        // ikisi de okunmaz hâle geliyordu.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 18) {
                                PanelNetworkProcessList(reduceMotion: reduceMotion)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                SpeedTestSection(network: controller.network)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minWidth: 820)

                            VStack(alignment: .leading, spacing: 18) {
                                PanelNetworkProcessList(reduceMotion: reduceMotion)
                                SpeedTestSection(network: controller.network)
                            }
                        }
                    }

                case .battery:
                    section(isLast: true) {
                        PanelBatteryView(
                            battery: controller.battery,
                            reduceMotion: reduceMotion,
                            animation: animation,
                            isWide: true
                        )
                    }

                case .disk:
                    section(isLast: true) {
                        PanelDiskView(
                            disk: controller.disk,
                            reduceMotion: reduceMotion,
                            animation: animation,
                            isWide: true
                        )
                    }

                case .processor:
                    // İşlemci sayfasının kendi panosu var: panelin tek
                    // sütunlu bileşeni yerine pencerenin genişliğini kullanan
                    // eşit genişlikte iki sütun (bkz. `ProcessorDashboardView`).
                    ProcessorDashboardView(
                        cpu: controller.cpu,
                        battery: controller.battery,
                        uptime: controller.device.uptime,
                        reduceMotion: reduceMotion,
                        animation: animation
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(title)
        // Alt başlık pencere başlığında değil, üst şeritteki sayfa
        // rozetinin altında görünüyor.
        .pageSubtitle(subtitle)
        // Ölçüm aboneliği sayfayla birlikte açılıp kapanıyor; denetleyici
        // sayaçlı olduğu için panel de açıksa ikinci bir döngü kurulmuyor.
        .task { controller.start() }
        .onDisappear { controller.stop() }
    }

    /// Sayfanın okunur genişliği.
    ///
    /// İşlemci panosu ızgara biçiminde: satır uzunluğu okunabilirliği
    /// bozmadığı için sayfanın tamamına yayılıyor. Disk sayfası kart ve
    /// sütunlardan oluşuyor, dar bir sütunda iki yanında kocaman boşluk
    /// kalıyordu — o da daha geniş. Ağ ve batarya ise metin ağırlıklı tek
    /// sütun akışı; onlar okunur bir ölçüde kalıyor.
    private var contentWidth: CGFloat {
        switch metric {
        case .processor: .infinity
        // Disk sayfası da ızgaraya geçti: kartlar ve liste sütunları
        // pencereyle birlikte çoğalıyor, sabit bir sütunda sıkışmıyor.
        case .disk: .infinity
        // Ağ sayfası da iki sütuna açıldı; dar bir sütunda sıkışmasın.
        case .network: .infinity
        case .battery: 640
        }
    }

    private var title: String {
        switch metric {
        case .network: L10n.networkActivityLabel
        case .battery: L10n.batteryLabel
        case .disk: L10n.diskLabel
        case .processor: L10n.processorBatteryTitle
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
