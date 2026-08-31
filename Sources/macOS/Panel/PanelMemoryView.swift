import SwiftUI
import GlassDoKit

/// Kenar panelindeki RAM görünümü. Ana penceredeki sistem monitörüyle aynı
/// veriyi kullanır fakat 329 pt panel için daha sıkı bir bilgi hiyerarşisi
/// uygular.
struct PanelMemoryView: View {
    private let controller = SystemMonitorController.shared
    @State private var confirmingQuit: pid_t?
    @State private var confirmResetTask: _Concurrency.Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let confirmWindow: Duration = .seconds(3)

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static func text(_ bytes: UInt64) -> String {
        formatter.string(fromByteCount: Int64(bytes))
    }

    private var segments: [PanelMemorySegment] {
        let memory = controller.memory
        return [
            PanelMemorySegment(id: .apps, label: L10n.memoryAppsLabel,
                               bytes: controller.appsTotal, color: MemoryPalette.apps),
            PanelMemorySegment(id: .system, label: L10n.memorySystemLabel,
                               bytes: controller.systemTotal, color: MemoryPalette.system),
            PanelMemorySegment(id: .cached, label: L10n.memoryCachedLabel,
                               bytes: memory.cached, color: MemoryPalette.cached),
            PanelMemorySegment(id: .free, label: L10n.memoryFreeLabel,
                               bytes: memory.free, color: MemoryPalette.free),
        ]
    }

    private var dataAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            Divider().opacity(0.25)
            appsSection
        }
        .frame(
            width: PanelSettings.panelWidth,
            height: PanelSettings.effectivePanelHeight,
            alignment: .top
        )
        .task { controller.start() }
        .onDisappear {
            controller.stop()
            confirmResetTask?.cancel()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.systemMonitorTitle)
                    .font(.system(size: 15, weight: .semibold))

                Spacer(minLength: 8)

                Text(percentText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.text(controller.memory.used))
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.4)
                    .contentTransition(reduceMotion ? .identity : .numericText())

                Text("/ \(Self.text(controller.memory.total))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            breakdownBar
            legend
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .animation(dataAnimation, value: controller.memory)
        .accessibilityElement(children: .contain)
    }

    private var percentText: String {
        let percent = Int((controller.memory.usedFraction * 100).rounded())
        return "%\(percent)"
    }

    private var breakdownBar: some View {
        let total = max(Double(controller.memory.total), 1)
        let used = segments.filter { $0.id != .free }

        return GeometryReader { geo in
            let spacing: CGFloat = 2
            let gaps = spacing * CGFloat(max(used.count - 1, 0))
            let available = max(geo.size.width - gaps, 0)

            ZStack(alignment: .leading) {
                Capsule().fill(MemoryPalette.free)

                HStack(spacing: spacing) {
                    ForEach(used) { segment in
                        let fraction = Double(segment.bytes) / total
                        Capsule()
                            .fill(segment.color)
                            .frame(width: fraction > 0.002 ? max(available * fraction, 4) : 0)
                    }
                }
            }
        }
        .frame(height: 8)
        .animation(dataAnimation, value: controller.memory)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10, alignment: .leading),
                GridItem(.flexible(), spacing: 10, alignment: .leading),
            ],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(segments) { segment in
                HStack(spacing: 7) {
                    Circle()
                        .fill(segment.color)
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(segment.label)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(Self.text(segment.bytes))
                            .font(.system(size: 11.5, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .animation(dataAnimation, value: controller.memory)
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.runningAppsLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.45)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Spacer()

                Text("\(controller.apps.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if controller.apps.isEmpty {
                emptyState
            } else {
                appList
            }
        }
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(controller.apps) { app in
                    PanelAppUsageRow(
                        app: app,
                        fraction: fraction(of: app),
                        valueText: Self.text(app.memoryBytes),
                        isConfirmingQuit: confirmingQuit == app.id,
                        onBeginQuit: { beginConfirming(app) },
                        onConfirmQuit: { confirmQuit(app) }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .mask(scrollEdgeMask)
    }

    private func fraction(of app: RunningAppUsage) -> Double {
        let largest = controller.largestAppMemory
        guard largest > 0 else { return 0 }
        return Double(app.memoryBytes) / Double(largest)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "memorychip")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.systemMonitorEmpty)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func beginConfirming(_ app: RunningAppUsage) {
        confirmResetTask?.cancel()
        withAnimation(Motion.toggle) { confirmingQuit = app.id }
        confirmResetTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: Self.confirmWindow)
            guard !_Concurrency.Task.isCancelled else { return }
            withAnimation(Motion.toggle) { confirmingQuit = nil }
        }
    }

    private func confirmQuit(_ app: RunningAppUsage) {
        confirmResetTask?.cancel()
        confirmingQuit = nil
        controller.quit(app)
    }

    private var scrollEdgeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black, location: 0.03),
                .init(color: .black, location: 0.97),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct PanelMemorySegment: Identifiable {
    enum Kind { case apps, system, cached, free }

    let id: Kind
    let label: String
    let bytes: UInt64
    let color: Color
}

private struct PanelAppUsageRow: View {
    let app: RunningAppUsage
    let fraction: Double
    let valueText: String
    let isConfirmingQuit: Bool
    let onBeginQuit: () -> Void
    let onConfirmQuit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            appIcon

            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 6)

            if isConfirmingQuit {
                confirmButton
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Text(valueText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .identity : .numericText())

                quitButton
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 35)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let image = app.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        }
    }

    private var quitButton: some View {
        Button(action: onBeginQuit) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isHovering ? Color.red : Color.secondary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.10 : 0.06)))
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0.55)
        .help(L10n.quitAppHelp(app.name))
        .accessibilityLabel(L10n.quitAppHelp(app.name))
    }

    private var confirmButton: some View {
        Button(action: onConfirmQuit) {
            Text(L10n.quit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.red))
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(L10n.quitAppHelp(app.name))
    }

    private var rowBackground: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.075 : 0.025))

                Capsule()
                    .fill(MemoryPalette.apps.opacity(isHovering ? 0.75 : 0.45))
                    .frame(width: max((geo.size.width - 14) * fraction, 2), height: 2)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 1)
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1.0),
            value: fraction
        )
    }
}
