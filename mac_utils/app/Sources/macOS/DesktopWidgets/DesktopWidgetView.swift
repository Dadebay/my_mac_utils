import GlassDoKit
import SwiftUI

/// Masaüstündeki bir widget'ın içeriği.
///
/// Panodaki kartın aynısını çiziyor — ayrı bir "widget sürümü" yazılsaydı
/// pano değiştikçe ikisi birbirinden ayrılırdı. Tek fark kabuğu: pencerenin
/// kendi camı, yuvarlatılmış köşesi ve üzerine gelince beliren kapatma
/// düğmesi.
struct DesktopWidgetView: View {
    let kind: DesktopWidgetKind
    let onClose: () -> Void

    private let controller = SystemStatsController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var animation: Animation? {
        reduceMotion ? nil : Motion.dataUpdate
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    var body: some View {
        card
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ChromeAmbience(placement: .widget)
                    .background(.ultraThinMaterial)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
            }
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    closeButton
                        .padding(9)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            // Ölçüm aboneliği pencereyle birlikte açılıp kapanıyor; sayaçlı
            // denetleyici olduğu için pano da açıksa ikinci bir döngü
            // kurulmuyor.
            .task { controller.start() }
            .onDisappear { controller.stop() }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 18, height: 18)
                .background { Circle().fill(.black.opacity(0.45)) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L10n.close)
        .accessibilityLabel(L10n.close)
    }

    /// Kartların `onOpenSettings`/`onDetach` eylemleri burada yok: widget
    /// zaten çıkarılmış durumda ve ayarları açmak uygulamayı öne
    /// getirirdi — widget'ın amacı tam da öne getirmeden okumak.
    @ViewBuilder
    private var card: some View {
        switch kind {
        case .processor:
            ProcessorCard(cpu: controller.cpu, reduceMotion: reduceMotion)

        case .memory:
            MemoryCard(
                memory: controller.memory,
                reduceMotion: reduceMotion,
                animation: animation
            )

        case .network:
            NetworkCard(
                // Hız testi widget'ta yok: gerçek trafik harcayan bir
                // eylemin masaüstünde tek tıkla durması istenmez.
                showsSpeedTest: false,
                network: controller.network,
                reduceMotion: reduceMotion
            )

        case .networkActivity:
            NetworkActivityCard(network: controller.network, reduceMotion: reduceMotion)

        case .battery:
            BatteryCard(
                battery: controller.battery,
                reduceMotion: reduceMotion,
                animation: animation
            )

        case .batteryHealth:
            BatteryHealthCard(
                battery: controller.battery,
                reduceMotion: reduceMotion,
                animation: animation
            )

        case .disk:
            DiskCard(
                disk: controller.disk,
                reduceMotion: reduceMotion,
                animation: animation
            )
        }
    }
}
