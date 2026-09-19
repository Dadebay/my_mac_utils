import SwiftUI
import GlassDoKit

/// Ağ görünümlerinin altına eklenen hız testi bölümü. Ana penceredeki kart
/// ile dar paneldeki görünüm aynı bileşeni paylaşır; `isCompact` yalnızca
/// yerleşimi sıkıştırır, bilgiyi eksiltmez.
struct SpeedTestSection: View {
    var isCompact = false
    /// Yerel adres ve arayüz adı ölçüm akışından geliyor; burada ikinci
    /// bir okuma yapılmıyor.
    var network = NetworkStats()

    @State private var controller = SpeedTestController.shared
    private let identity = NetworkIdentityController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { Color(red: 0.36, green: 0.64, blue: 0.98) }

    var body: some View {
        if isCompact {
            compactBody
        } else {
            wideBody
        }
    }

    /// Geniş yerleşim: kadran ve altında sonuçlar. Yanında "nasıl
    /// çalışıyor" sütunu vardı; testi başlatan düğme de oradaydı. İkisi de
    /// kalktı — kadranın kendisi düğme ve tek bir ölçümün yanında bir
    /// paragraf açıklama, ölçümden çok yer kaplıyordu.
    private var wideBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.speedTestTitle)
                .font(.app(size: 17, weight: .semibold))

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    gaugeStack
                    connectionColumn
                }
                .frame(minWidth: 520)

                VStack(alignment: .leading, spacing: 18) {
                    gaugeStack
                    connectionColumn
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: controller.phase)
        .task { await identity.refreshIfNeeded() }
    }

    private var gaugeStack: some View {
        VStack(spacing: 14) {
            gaugeColumn

            if case .finished = controller.phase {
                wideResults
            }

            if case .failed(let reason) = controller.phase {
                message(L10n.speedTestFailed(reason), isError: true)
            }

            if case .cancelled = controller.phase {
                message(L10n.speedTestCancelled)
            }

            // Uyarı duruyor: test gerçek veri harcıyor, bunu söylemek
            // açıklama değil, kullanıcıyı koruyan bilgi.
            Text(L10n.speedTestTrafficNote)
                .font(.app(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var gaugeColumn: some View {
        SpeedTestGauge(
            bitsPerSecond: controller.isRunning
                ? controller.liveBitsPerSecond
                : (controller.downloadBitsPerSecond ?? 0),
            progress: controller.progress,
            isRunning: controller.isRunning,
            caption: gaugeCaption,
            diameter: isCompact ? 124 : 168,
            accent: accent,
            actionTitle: gaugeActionTitle,
            // Ayrı bir "Durdur" düğmesi yok: kadran sürerken de tıklanabilir
            // ve testi kesiyor.
            action: { controller.isRunning ? controller.cancel() : controller.start() }
        )
    }

    /// Kadranın yanındaki bağlantı kimliği: makinenin ağdaki yerel adresi,
    /// VPN ayaktaysa hangisi olduğu ve internetin bizi hangi adresle
    /// gördüğü. Üçü yan yana durunca "VPN açık mı ve gerçekten çalışıyor
    /// mu" sorusu tek bakışta yanıtlanıyor.
    private var connectionColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(L10n.networkConnectionLabel)
                    .font(.app(size: 10, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Button {
                    _Concurrency.Task { await identity.refresh() }
                } label: {
                    HugeIcon(name: .refresh, size: 12)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .disabled(identity.isLookingUp)
                .help(L10n.refreshLabel)
                .accessibilityLabel(L10n.refreshLabel)
            }

            publicRow
            vpnRow
            localRow

            Text(L10n.publicIPSourceNote)
                .font(.app(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var publicRow: some View {
        identityRow(
            label: L10n.publicIPLabel,
            value: identity.publicAddress ?? (identity.isLookingUp ? "…" : L10n.publicIPUnavailable),
            detail: identity.publicRegion,
            tint: identity.lookupFailed ? SystemPalette.warning : accent,
            isMonospaced: identity.publicAddress != nil
        )
    }

    private var vpnRow: some View {
        identityRow(
            label: L10n.vpnLabel,
            value: identity.vpn.isActive
                ? (identity.vpn.displayName ?? L10n.vpnActive)
                : L10n.vpnInactive,
            detail: identity.vpn.interfaceName,
            tint: identity.vpn.isActive ? SystemPalette.positive : .secondary,
            isMonospaced: false
        )
    }

    private var localRow: some View {
        identityRow(
            label: L10n.localIPLabel,
            value: network.localAddress.isEmpty ? "—" : network.localAddress,
            detail: network.interfaceName.isEmpty ? nil : network.interfaceName,
            tint: .secondary,
            isMonospaced: !network.localAddress.isEmpty
        )
    }

    /// Adresler eşaralıklı yazılıyor: rakam genişlikleri sabit olunca üç
    /// satır alt alta hizalı okunuyor.
    private func identityRow(
        label: String,
        value: String,
        detail: String?,
        tint: Color,
        isMonospaced: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .offset(y: -1)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.app(size: 10.5))
                    .foregroundStyle(.tertiary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(
                            isMonospaced
                                ? .system(size: 13, weight: .medium, design: .monospaced)
                                : .app(size: 13, weight: .medium)
                        )
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.app(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background {
                                Capsule().fill(Color.primary.opacity(0.07))
                            }
                    }
                }
            }
        }
    }

    private var gaugeActionTitle: String {
        if controller.isRunning { return L10n.speedTestStop }
        return controller.downloadBitsPerSecond == nil ? L10n.speedTestStart : L10n.speedTestRetry
    }

    /// Geniş alanda dört ölçüm tek sırada: dar paneldeki 2×2 düzen burada
    /// kutunun yarısını boş bırakıyordu.
    private var wideResults: some View {
        HStack(spacing: 8) {
            resultTile(
                symbolName: "arrow.down",
                label: L10n.networkDownloadLabel,
                value: Self.megabits(controller.downloadBitsPerSecond ?? 0),
                unit: "Mbps",
                color: accent
            )
            resultTile(
                symbolName: "arrow.up",
                label: L10n.networkUploadLabel,
                value: Self.megabits(controller.uploadBitsPerSecond ?? 0),
                unit: "Mbps",
                color: Color(red: 0.55, green: 0.45, blue: 0.95)
            )
            resultTile(
                symbolName: "timer",
                label: L10n.speedTestLatencyLabel,
                value: Self.milliseconds(controller.latencyMs ?? 0),
                unit: "ms",
                color: Color(red: 0.34, green: 0.78, blue: 0.48)
            )
            resultTile(
                symbolName: "waveform.path",
                label: L10n.speedTestJitterLabel,
                value: Self.milliseconds(controller.jitterMs ?? 0),
                unit: "ms",
                color: Color(red: 1.0, green: 0.72, blue: 0.22)
            )
        }
    }

    /// Kadranın altındaki satır: sürerken hangi evrede olduğunu, bittiğinde
    /// ne ölçüldüğünü söylüyor.
    private var gaugeCaption: String {
        switch controller.phase {
        case .idle: L10n.speedTestStart
        case .latency, .download, .upload: phaseLabel
        case .finished: L10n.networkDownloadLabel
        case .cancelled: L10n.speedTestCancelled
        case .failed: L10n.speedTestRetry
        }
    }

    /// Dar yerleşim (menü çubuğu kartı ve kenar paneli): aynı kadran,
    /// küçültülmüş. Önceden burada düz bir "Testi Başlat" düğmesi ve
    /// altında ilerleme çubuğu vardı; kadran ikisinin işini birden
    /// görüyor ve ana penceredeki görünümle aynı dili konuşuyor.
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            gaugeColumn
                .frame(maxWidth: .infinity)

            switch controller.phase {
            case .finished:
                results
            case .cancelled:
                message(L10n.speedTestCancelled)
            case .failed(let reason):
                message(L10n.speedTestFailed(reason), isError: true)
            case .idle, .latency, .download, .upload:
                EmptyView()
            }

            Text(L10n.speedTestTrafficNote)
                .font(.app(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: controller.phase)
    }

    // MARK: - Parçalar

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "speedometer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
            Text(L10n.speedTestLabel)
                .font(.app(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                resultTile(
                    symbolName: "arrow.down",
                    label: L10n.networkDownloadLabel,
                    value: Self.megabits(controller.downloadBitsPerSecond ?? 0),
                    unit: "Mbps",
                    color: accent
                )
                resultTile(
                    symbolName: "arrow.up",
                    label: L10n.networkUploadLabel,
                    value: Self.megabits(controller.uploadBitsPerSecond ?? 0),
                    unit: "Mbps",
                    color: Color(red: 0.55, green: 0.45, blue: 0.95)
                )
            }

            HStack(spacing: 8) {
                resultTile(
                    symbolName: "timer",
                    label: L10n.speedTestLatencyLabel,
                    value: Self.milliseconds(controller.latencyMs ?? 0),
                    unit: "ms",
                    color: Color(red: 0.34, green: 0.78, blue: 0.48)
                )
                resultTile(
                    symbolName: "waveform.path",
                    label: L10n.speedTestJitterLabel,
                    value: Self.milliseconds(controller.jitterMs ?? 0),
                    unit: "ms",
                    color: Color(red: 1.0, green: 0.72, blue: 0.22)
                )
            }
        }
    }

    private func resultTile(
        symbolName: String, label: String, value: String, unit: String, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(color.opacity(0.16)))

                Text(label)
                    .font(.app(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.app(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unit)
                    .font(.app(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private func message(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.app(size: 10.5))
            .foregroundStyle(isError ? Color.red.opacity(0.9) : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var phaseLabel: String {
        switch controller.phase {
        case .latency: L10n.speedTestPhaseLatency
        case .download: L10n.speedTestPhaseDownload
        case .upload: L10n.speedTestPhaseUpload
        default: ""
        }
    }

    // MARK: - Biçimlendirme

    private static func megabits(_ bitsPerSecond: Double) -> String {
        let mbps = max(bitsPerSecond, 0) / 1_000_000
        // Yüzün altında ondalık bilgi taşır; üstünde gürültüye dönüşür.
        return mbps >= 100
            ? String(format: "%.0f", mbps)
            : String(format: "%.1f", mbps)
    }

    private static func milliseconds(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
