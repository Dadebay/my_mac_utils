import SwiftUI
import GlassDoKit

/// Bütün sistem ölçerlerini tek sütunda, ayraçlarla bölünmüş kartlar hâlinde
/// gösterir. Kartlar arasında kutu içinde kutu görüntüsü oluşmasın diye
/// çerçeve değil ayraç kullanılıyor — referans tasarımdaki gibi tek bir
/// yüzey üzerinde okunur.
struct SystemDashboardView: View {
    private let controller = SystemStatsController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1.0)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                section {
                    ProcessorCard(
                        cpu: controller.cpu,
                        reduceMotion: reduceMotion,
                        onOpenSettings: { openSettings() }
                    )
                }

                section {
                    MemoryCard(
                        memory: controller.memory,
                        reduceMotion: reduceMotion,
                        animation: animation,
                        onOpenSettings: { openSettings() }
                    )
                }

                section {
                    NetworkCard(
                        network: controller.network,
                        reduceMotion: reduceMotion,
                        onOpenSettings: { openSettings() }
                    )
                }

                section {
                    NetworkActivityCard(
                        network: controller.network,
                        reduceMotion: reduceMotion,
                        onOpenSettings: { openSettings() }
                    )
                }

                section {
                    SpeedTestSection()
                }

                section {
                    BatteryCard(
                        battery: controller.battery,
                        reduceMotion: reduceMotion,
                        animation: animation,
                        onOpenSettings: { openSettings() }
                    )
                }

                section {
                    BatteryHealthCard(
                        battery: controller.battery,
                        reduceMotion: reduceMotion,
                        animation: animation,
                        onOpenSettings: { openSettings() }
                    )
                }

                section(isLast: true) {
                    DiskCard(
                        disk: controller.disk,
                        reduceMotion: reduceMotion,
                        animation: animation,
                        onOpenSettings: { openSettings() }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            // Sütun çok genişlediğinde büyük başlıklar sayfanın solunda
            // yalnız kalıyor; okunur bir ölçüde tutuluyor.
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(L10n.systemOverviewTitle)
        .task { controller.start() }
        .onDisappear { controller.stop() }
    }

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
