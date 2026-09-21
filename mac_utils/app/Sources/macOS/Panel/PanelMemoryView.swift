import SwiftUI
import GlassDoKit

/// Kenar panelindeki RAM görünümü. Ana penceredeki sistem monitörüyle aynı
/// veriyi kullanır fakat 329 pt panel için daha sıkı bir bilgi hiyerarşisi
/// uygular.
struct PanelMemoryView: View {
    private let controller = SystemMonitorController.shared
    @State private var confirmingQuit: pid_t?
    /// Göstergede seçili dilim: alttaki liste bunu gösteriyor. Varsayılan
    /// "Uygulamalar" — panelin asıl sorusu genelde "hangi uygulama yiyor".
    @State private var selection: PanelMemorySegment.Kind = .apps
    @State private var confirmResetTask: _Concurrency.Task<Void, Never>?
    /// Liste satırlarının alttan akarak belirmesi. Panel açıldığında (ve
    /// dilim değiştiğinde) sıfırlanıp yeniden oynatılıyor.
    @State private var isListRevealed = false
    @State private var revealTask: _Concurrency.Task<Void, Never>?
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
            revealTask?.cancel()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.systemMonitorTitle)
                    .font(.app(size: 15, weight: .semibold))

                Spacer(minLength: 8)

                Text(percentText)
                    .font(.app(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.text(controller.memory.used))
                    .font(.app(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.4)
                    .contentTransition(reduceMotion ? .identity : .numericText())

                Text("/ \(Self.text(controller.memory.total))")
                    .font(.app(size: 11, weight: .medium))
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
                            // Seçili dilim tam renkte, diğerleri geri
                            // çekiliyor: göstergeye basmak listeyi de
                            // çubuğu da değiştiriyor.
                            .opacity(segment.id == selection ? 1 : 0.34)
                            .frame(width: fraction > 0.002 ? max(available * fraction, 4) : 0)
                    }
                }
            }
        }
        .frame(height: 8)
        .animation(dataAnimation, value: controller.memory)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection)
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
                legendItem(segment)
            }
        }
        .animation(dataAnimation, value: controller.memory)
    }

    /// Yalnızca süreç listesi olan iki dilim seçilebiliyor: önbellek ve boş
    /// bellek bir sürecin değil çekirdeğin muhasebesi, onlara basınca
    /// gösterilecek liste yok.
    private func isSelectable(_ kind: PanelMemorySegment.Kind) -> Bool {
        kind == .apps || kind == .system
    }

    private func legendItem(_ segment: PanelMemorySegment) -> some View {
        let isSelected = segment.id == selection
        let selectable = isSelectable(segment.id)

        return Button {
            guard selectable else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                selection = segment.id
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(segment.color)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(segment.label)
                        .font(.app(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(Self.text(segment.bytes))
                        .font(.app(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? segment.color.opacity(0.16) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? segment.color.opacity(0.5) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Seçili dilimin süreçleri. Panelde liste kısa: en çok yiyen on tanesi
    /// zaten kararı verdiriyor.
    private var visibleProcesses: [RunningAppUsage] {
        let source = selection == .system ? controller.systemProcesses : controller.apps
        return Array(source.prefix(10))
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selection == .system ? L10n.systemProcessesLabel : L10n.runningAppsLabel)
                    .font(.app(size: 10, weight: .semibold))
                    .kerning(0.45)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Spacer()

                Text("\(visibleProcesses.count)")
                    .font(.app(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if visibleProcesses.isEmpty {
                emptyState
            } else {
                appList
            }
        }
    }

    /// Liste en çok on satır: `LazyVStack` yerine düz `VStack`, çünkü
    /// tembel yığın ekrana girmemiş satırı hiç kurmuyor — sırayla beliren
    /// bir listede kurulmamış satırın animasyonu da olmuyordu.
    private var appList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(visibleProcesses.enumerated()), id: \.element.id) { index, app in
                    PanelAppUsageRow(
                        app: app,
                        fraction: fraction(of: app),
                        valueText: Self.text(app.memoryBytes),
                        isConfirmingQuit: confirmingQuit == app.id,
                        onBeginQuit: { beginConfirming(app) },
                        onConfirmQuit: { confirmQuit(app) }
                    )
                    .modifier(RowReveal(
                        index: index,
                        isRevealed: isListRevealed,
                        reduceMotion: reduceMotion
                    ))
                    // Ölçüm yenilenince listeye giren/çıkan satır da
                    // aynı yönden geliyor: sıralama değişimi yerinde
                    // kayarak, yeni satır alttan.
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity
                    ))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            .animation(
                reduceMotion ? nil : Motion.dataUpdate,
                value: visibleProcesses.map(\.id)
            )
        }
        .mask(scrollEdgeMask)
        .onAppear(perform: replayReveal)
        .onChange(of: selection) { _, _ in replayReveal() }
    }

    /// Satırları baştan, sırayla belirtir.
    ///
    /// `false → true` aynı karede yapılırsa SwiftUI ikisini tek
    /// güncellemede birleştiriyor ve satırlar hiç hareket etmeden
    /// görünüyor; bir kare beklenince hareket gerçekten oynuyor.
    private func replayReveal() {
        revealTask?.cancel()
        isListRevealed = false
        revealTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .milliseconds(16))
            guard !_Concurrency.Task.isCancelled else { return }
            isListRevealed = true
        }
    }

    /// Satırdaki oran çubuğu **gösterilen** listenin tepesine göre
    /// ölçekleniyor; uygulama listesinin tepesine göre olsaydı sistem
    /// süreçleri hep silik görünürdü.
    private func fraction(of app: RunningAppUsage) -> Double {
        let largest = visibleProcesses.first?.memoryBytes ?? 0
        guard largest > 0 else { return 0 }
        return Double(app.memoryBytes) / Double(largest)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "memorychip")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.systemMonitorEmpty)
                .font(.app(size: 12))
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

/// Satırı alttan yukarı, sırasına göre gecikmeli olarak getirir.
///
/// Liste tek blok hâlinde beliriyordu: veri geldiği anda on satır aynı
/// karede ekrana basılıyor, panelin kendi açılma hareketiyle çakışıp
/// "yapışmış" görünüyordu. Sıra numarasına bağlı küçük bir gecikme,
/// aynı veriyi akan bir hareket hâline getiriyor.
private struct RowReveal: ViewModifier {
    let index: Int
    let isRevealed: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed ? 0 : 16)
            .animation(animation, value: isRevealed)
    }

    /// Yalnızca geliş animasyonlu. Sıfırlama (dilim değişince, panel
    /// yeniden açılınca) anında olmalı: geri dönüşü de canlandırmak,
    /// iki listenin ortasında satırların aşağı sarkıp geri gelmesi gibi
    /// görünüyordu.
    private var animation: Animation? {
        guard isRevealed, !reduceMotion else { return nil }
        return Motion.listReveal.delay(Double(index) * Motion.listRevealStagger)
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
                .font(.app(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 6)

            if isConfirmingQuit {
                confirmButton
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Text(valueText)
                    .font(.app(size: 11, weight: .semibold))
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
                .font(.app(size: 10, weight: .semibold))
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
