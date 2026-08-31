import SwiftUI
import GlassDoKit

/// Ağ görünümlerinin altına eklenen hız testi bölümü. Ana penceredeki kart
/// ile dar paneldeki görünüm aynı bileşeni paylaşır; `isCompact` yalnızca
/// yerleşimi sıkıştırır, bilgiyi eksiltmez.
struct SpeedTestSection: View {
    var isCompact = false

    @State private var controller = SpeedTestController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { Color(red: 0.36, green: 0.64, blue: 0.98) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            switch controller.phase {
            case .idle:
                idleState
            case .latency, .download, .upload:
                runningState
            case .finished:
                results
                actionButton(L10n.speedTestRetry, symbol: "arrow.clockwise", isDestructive: false) { controller.start() }
            case .cancelled:
                message(L10n.speedTestCancelled)
                actionButton(L10n.speedTestRetry, symbol: "arrow.clockwise", isDestructive: false) { controller.start() }
            case .failed(let reason):
                message(L10n.speedTestFailed(reason), isError: true)
                actionButton(L10n.speedTestRetry, symbol: "arrow.clockwise", isDestructive: false) { controller.start() }
            }
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
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionButton(L10n.speedTestStart, symbol: "play.fill", isDestructive: false) { controller.start() }

            Text(L10n.speedTestTrafficNote)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var runningState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(phaseLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Self.megabits(controller.liveBitsPerSecond))
                    .font(.system(size: isCompact ? 22 : 26, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .contentTransition(reduceMotion ? .identity : .numericText())

                Text("Mbps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: controller.progress)
                .progressViewStyle(.linear)
                .tint(accent)

            actionButton(L10n.speedTestStop, symbol: "stop.fill", isDestructive: true) { controller.cancel() }
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
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unit)
                    .font(.system(size: 9))
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

    private func actionButton(
        _ title: String,
        symbol: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let tint = isDestructive ? Color.red : accent

        return Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 25, height: 25)
                    .background {
                        Circle()
                            .fill(tint.opacity(0.15))
                            .overlay {
                                Circle().strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
                            }
                    }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDestructive ? tint : Color.primary)

                Spacer(minLength: 0)

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isDestructive ? tint.opacity(0.07) : Color.primary.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                isDestructive ? tint.opacity(0.16) : Color.white.opacity(0.075),
                                lineWidth: 0.5
                            )
                    }
            }
        }
        .buttonStyle(.pressScale(reduceMotion ? 1 : 0.98))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func message(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10.5))
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
