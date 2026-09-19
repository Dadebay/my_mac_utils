import SwiftUI
import GlassDoKit

/// Bütün sistem ölçerlerini tek sütunda, ayraçlarla bölünmüş kartlar hâlinde
/// gösterir. Kartlar arasında kutu içinde kutu görüntüsü oluşmasın diye
/// çerçeve değil ayraç kullanılıyor — referans tasarımdaki gibi tek bir
/// yüzey üzerinde okunur.
struct SystemDashboardView: View {
    private let controller = SystemStatsController.shared
    private let widgets = DesktopWidgetController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    private var animation: Animation? {
        reduceMotion ? nil : Motion.dataUpdate
    }

    var body: some View {
        ScrollView {
            // Kartlar tek bir dar sütunda ayraçlarla değil, pencereyle
            // birlikte çoğalan sütunlarda duruyor — "CPU & Batarya"
            // sayfasıyla aynı düzen dili. Sütun sayısını `.adaptive`
            // belirliyor: kart 360 pt'nin altına inmiyor, artan yer yeni
            // bir sütuna gidiyor.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 330), spacing: 14)],
                alignment: .leading,
                spacing: 14
            ) {
                ProcessorCard(
                    cpu: controller.cpu,
                    reduceMotion: reduceMotion,
                    onOpenSettings: { openSettings() },
                    onDetach: { widgets.open(.processor) }
                )
                .dashboardCard()

                MemoryCard(
                    memory: controller.memory,
                    reduceMotion: reduceMotion,
                    animation: animation,
                    onOpenSettings: { openSettings() },
                    onDetach: { widgets.open(.memory) }
                )
                .dashboardCard()

                NetworkCard(
                    // Hız testi panoda kendi kartında; burada ikinci kez
                    // görünmesin.
                    showsSpeedTest: false,
                    network: controller.network,
                    reduceMotion: reduceMotion,
                    onOpenSettings: { openSettings() },
                    onDetach: { widgets.open(.network) }
                )
                .dashboardCard()

                NetworkActivityCard(
                    network: controller.network,
                    reduceMotion: reduceMotion,
                    onOpenSettings: { openSettings() },
                    onDetach: { widgets.open(.networkActivity) }
                )
                .dashboardCard()

                SpeedTestSection(network: controller.network)
                    .dashboardCard()

                BatteryCard(
                    battery: controller.battery,
                    reduceMotion: reduceMotion,
                    animation: animation,
                    onOpenSettings: { openSettings() },
                    onDetach: { widgets.open(.battery) }
                )
                .dashboardCard()

                BatteryHealthCard(
                    battery: controller.battery,
                    reduceMotion: reduceMotion,
                    animation: animation,
                    onOpenSettings: { openSettings() },
                    onDetach: { widgets.open(.batteryHealth) }
                )
                .dashboardCard()

                DiskCard(
                    disk: controller.disk,
                    reduceMotion: reduceMotion,
                    animation: animation,
                    onOpenSettings: { openSettings() },
                    onDetach: { widgets.open(.disk) }
                )
                .dashboardCard()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background { ChromeAmbience(placement: .content) }
        .navigationTitle(L10n.systemOverviewTitle)
        .task { controller.start() }
        .onDisappear { controller.stop() }
    }

}
