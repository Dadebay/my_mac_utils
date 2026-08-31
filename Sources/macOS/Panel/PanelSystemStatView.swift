import SwiftUI
import AppKit
import GlassDoKit

/// Kenar panelindeki tek ölçer görünümü. Ana penceredeki panoyla aynı
/// kartları kullanır — dar panel için ayrı bir tasarım tutmak ikisinin
/// zamanla birbirinden ayrılmasına yol açardı. Panel yalnızca ray ikonunun
/// seçtiği ölçeri gösterir.
struct PanelSystemStatView: View {
    enum Metric {
        case network, battery, disk, processor
    }

    let metric: Metric

    private let controller = SystemStatsController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1.0)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch metric {
                case .network:
                    card {
                        PanelNetworkView(
                            network: controller.network,
                            reduceMotion: reduceMotion,
                            animation: animation
                        )
                    }
                    card { PanelNetworkProcessList(reduceMotion: reduceMotion) }
                    card(isLast: true) { SpeedTestSection(isCompact: true) }

                case .battery:
                    card(isLast: true) {
                        PanelBatteryView(
                            battery: controller.battery,
                            reduceMotion: reduceMotion,
                            animation: animation
                        )
                    }

                case .disk:
                    card(isLast: true) {
                        PanelDiskView(
                            disk: controller.disk,
                            reduceMotion: reduceMotion,
                            animation: animation
                        )
                    }

                case .processor:
                    card(isLast: true) {
                        PanelProcessorView(
                            cpu: controller.cpu,
                            memory: controller.memory,
                            reduceMotion: reduceMotion,
                            animation: animation
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .frame(
            width: PanelSettings.panelWidth,
            height: PanelSettings.effectivePanelHeight,
            alignment: .top
        )
        .task { controller.start() }
        .onDisappear { controller.stop() }
    }

    private func card<Content: View>(
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(.vertical, 14)

            if !isLast {
                Divider().opacity(0.3)
            }
        }
    }
}

// MARK: - Compact processor and memory

/// CPU ve belleği dar ray panelinde tek bakışta okunacak iki bağlı bölüm
/// olarak sunar. Anlık değerler önde, açıklayıcı kırılım ve geçmiş arkada.
struct PanelProcessorView: View {
    let cpu: CPULoadStats
    let memory: MemoryStats
    let reduceMotion: Bool
    let animation: Animation?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                symbol: "cpu",
                title: L10n.processorLoadLabel,
                subtitle: thermalText,
                tint: thermalTint
            )

            processorSummary
            processorBreakdown

            if !cpu.perCoreUsage.isEmpty {
                coreActivity
            }

            StatStackedBarChart(
                samples: cpu.layeredHistory,
                colors: [SystemPalette.accent, SystemPalette.secondary],
                height: 58,
                capacity: 34
            )

            Divider().opacity(0.25)

            panelHeader(
                symbol: "memorychip",
                title: L10n.memoryLabel,
                subtitle: memoryPressureText,
                tint: memoryTint
            )

            memorySummary
            memoryLegend

            StatStackedBarChart(
                samples: memory.history,
                colors: [SystemPalette.accent, SystemPalette.secondary, SystemPalette.tertiary],
                height: 52,
                capacity: 34
            )
        }
        .animation(animation, value: cpu)
        .animation(animation, value: memory)
    }

    /// Çekirdek başına yük: kompakt başlık, sağda en yoğun çekirdek, altında
    /// sütunlar. Panel dar olduğu için grafik 60 pt — sütunlar sıkışsa da
    /// hepsi görünür kalıyor, çünkü genişlik çekirdek sayısına bölünüyor.
    private var coreActivity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.processorCoreActivityLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let busiest = PerCoreLoadChart.busiest(in: cpu.perCoreUsage) {
                    Text(L10n.processorBusiestCore(busiest.number, busiest.usage))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            PerCoreLoadChart(
                usages: cpu.perCoreUsage,
                color: SystemPalette.accent,
                height: 60,
                animation: animation
            )
        }
    }

    private var processorSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SystemFormat.percent(cpu.usage))
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-1.4)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())

                Text(L10n.processorCoreSummary(cpu.coreCount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            ZStack {
                StatRingGauge(
                    fraction: cpu.usage,
                    color: thermalTint,
                    lineWidth: 8,
                    animation: animation
                )
                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(thermalTint)
            }
            .frame(width: 62, height: 62)
        }
        .padding(12)
        .background(panelSurface)
    }

    private var processorBreakdown: some View {
        HStack(spacing: 8) {
            compactValueTile(
                label: L10n.processorUserLabel,
                value: SystemFormat.percent(cpu.userUsage),
                color: SystemPalette.accent
            )
            compactValueTile(
                label: L10n.processorSystemLabel,
                value: SystemFormat.percent(cpu.systemUsage),
                color: SystemPalette.secondary
            )
        }
    }

    private var memorySummary: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SystemFormat.percent(memory.usedFraction))
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-1)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())

                Text("\(SystemFormat.memoryBytes(memory.used)) / \(SystemFormat.memoryBytes(memory.total))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }

            Spacer(minLength: 4)

            StatSegmentedRing(
                segments: [
                    (Double(memory.active) / Double(max(memory.total, 1)), SystemPalette.accent),
                    (Double(memory.wired) / Double(max(memory.total, 1)), SystemPalette.secondary),
                    (Double(memory.compressed) / Double(max(memory.total, 1)), SystemPalette.tertiary),
                ],
                lineWidth: 8,
                animation: animation
            )
            .frame(width: 62, height: 62)
        }
    }

    private var memoryLegend: some View {
        HStack(spacing: 8) {
            memoryItem(L10n.memoryActiveLabel, memory.active, SystemPalette.accent)
            memoryItem(L10n.memoryWiredLabel, memory.wired, SystemPalette.secondary)
            memoryItem(L10n.memoryCompressedLabel, memory.compressed, SystemPalette.tertiary)
        }
    }

    private func memoryItem(_ label: String, _ bytes: UInt64, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(SystemFormat.memoryBytes(bytes))
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactValueTile(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(panelSurface)
    }

    private var thermalText: String {
        switch cpu.thermalPressure {
        case .nominal: L10n.thermalNominal
        case .fair: L10n.thermalFair
        case .serious: L10n.thermalSerious
        case .critical: L10n.thermalCritical
        }
    }

    private var thermalTint: Color {
        switch cpu.thermalPressure {
        case .nominal: SystemPalette.positive
        case .fair: SystemPalette.warning
        case .serious, .critical: SystemPalette.danger
        }
    }

    private var memoryTint: Color {
        if memory.pressureFraction >= 0.8 { return SystemPalette.danger }
        if memory.pressureFraction >= 0.6 { return SystemPalette.warning }
        return SystemPalette.positive
    }

    private var memoryPressureText: String {
        "\(L10n.memoryPressureLabel) \(SystemFormat.percent(memory.pressureFraction, decimals: 0))"
    }
}

// MARK: - Compact battery

/// Bataryanın anlık durumu ile uzun vadeli sağlığını tek, sakin bir bilgi
/// akışında gösterir. Büyük pano kartları yerine dar panelin gerçek genişliği
/// için tasarlandığı için metinler kesilmez ve göstergeler rayın altına kaçmaz.
struct PanelBatteryView: View {
    let battery: BatteryStats
    let reduceMotion: Bool
    let animation: Animation?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                symbol: "battery.100percent",
                title: L10n.batteryLabel,
                subtitle: battery.isCharging ? L10n.batteryChargingLabel : adapterStatus,
                tint: battery.isCharging ? SystemPalette.positive : SystemPalette.accent
            )

            if battery.isPresent {
                chargeSurface
                electricalMetrics
                adapterRow

                Divider().opacity(0.25)

                healthSection
            } else {
                unavailablePanel(L10n.batteryUnavailable, symbol: "battery.slash")
            }
        }
        .animation(animation, value: battery)
    }

    private var chargeSurface: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(battery.chargePercent)%")
                        .font(.system(size: 42, weight: .semibold))
                        .tracking(-1.5)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())

                    Text("\(battery.charge) / \(battery.currentCapacity) mAh")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }

                Spacer(minLength: 4)

                CompactBatteryGauge(
                    fraction: Double(battery.chargePercent) / 100,
                    isCharging: battery.isCharging,
                    animation: animation
                )
                .frame(width: 82, height: 36)
            }

            HStack(spacing: 8) {
                compactPill(
                    L10n.batteryTemperatureLabel,
                    SystemFormat.decimals(battery.temperature, 0, unit: "°C"),
                    tint: temperatureTint
                )

                if let minutes = battery.minutesRemaining, !battery.isCharging {
                    compactPill("", L10n.batteryTimeRemaining(minutes))
                }
            }
        }
        .padding(12)
        .background(panelSurface)
    }

    private var electricalMetrics: some View {
        HStack(spacing: 8) {
            metric(L10n.batteryPowerLabel, SystemFormat.decimals(battery.power, 2, unit: "W"))
            metric(L10n.batteryAmperageLabel, SystemFormat.decimals(battery.amperage, 2, unit: "A"))
            metric(L10n.batteryVoltageLabel, SystemFormat.decimals(battery.voltage, 2, unit: "V"))
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var adapterRow: some View {
        HStack(spacing: 8) {
            Image(systemName: battery.isAdapterConnected ? "powerplug.fill" : "powerplug")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(battery.isAdapterConnected ? SystemPalette.positive : .secondary)

            Text(L10n.batteryAdapterLabel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            Text(adapterStatus)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader(
                symbol: "heart.text.square",
                title: L10n.batteryHealthLabel,
                subtitle: conditionText,
                tint: conditionColor
            )

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(SystemFormat.percent(battery.healthFraction, decimals: 0))
                        .font(.system(size: 34, weight: .semibold))
                        .tracking(-1)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())

                    Text("\(battery.currentCapacity) / \(battery.designCapacity) mAh")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    compactPill(L10n.batteryCyclesLabel, "\(battery.cycleCount)")
                }

                Spacer(minLength: 0)

                StatRingGauge(
                    fraction: battery.healthFraction,
                    color: conditionColor,
                    lineWidth: 8,
                    animation: animation
                )
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: conditionSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(conditionColor)
                }
            }
        }
    }

    private var adapterStatus: String {
        if battery.isCharging { return L10n.batteryChargingLabel }
        return battery.isAdapterConnected ? "—" : L10n.batteryAdapterDisconnected
    }

    private var temperatureTint: Color? {
        if battery.temperature >= 45 { return SystemPalette.danger }
        if battery.temperature >= 35 { return SystemPalette.warning }
        return nil
    }

    private var conditionText: String {
        switch battery.condition {
        case .perfect: L10n.batteryConditionPerfect
        case .good: L10n.batteryConditionGood
        case .fair: L10n.batteryConditionFair
        case .service: L10n.batteryConditionService
        }
    }

    private var conditionColor: Color {
        switch battery.condition {
        case .perfect, .good: SystemPalette.positive
        case .fair: SystemPalette.warning
        case .service: SystemPalette.danger
        }
    }

    private var conditionSymbol: String {
        battery.condition == .service ? "exclamationmark" : "checkmark"
    }
}

// MARK: - Compact disk

struct PanelDiskView: View {
    let disk: DiskStats
    let reduceMotion: Bool
    let animation: Animation?
    /// Kalıcı yüzeylerde (kenar paneli, ana pencere) dosya Çöp Kutusu'na
    /// taşınabiliyor. Menü çubuğu popover'ı `.transient`: dışarıya çıkan her
    /// etkileşimde kapanıyor, dolayısıyla onay penceresi açılırken altındaki
    /// bağlam kayboluyor — kullanıcı neyi sildiğini göremeden karar verirdi.
    /// Orada liste yalnızca okunuyor; Finder'da göstermek duruyor.
    var allowsDeletion = true

    @State private var analyzer = DiskSpaceAnalyzer.shared
    @State private var pendingDeletion: StorageCandidate?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                symbol: "internaldrive",
                title: L10n.diskLabel,
                subtitle: disk.volumeName.isEmpty ? nil : disk.volumeName,
                tint: usageTint
            )

            usageSurface

            HStack(spacing: 8) {
                capacityTile(label: L10n.diskUsedLabel, value: SystemFormat.bytes(disk.used), tint: usageTint)
                capacityTile(label: L10n.diskFreeLabel, value: SystemFormat.bytes(disk.free), tint: .secondary)
            }

            storageInspector
        }
        .animation(animation, value: disk)
        .task { analyzer.scanIfNeeded() }
        .alert(
            pendingDeletion.map { L10n.storageDeleteTitle($0.name) } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { item in
            Button(L10n.storageCancel, role: .cancel) {
                pendingDeletion = nil
            }
            Button(L10n.storageMoveToTrash, role: .destructive) {
                pendingDeletion = nil
                analyzer.moveToTrash(item)
            }
        } message: { _ in
            Text(L10n.storageDeleteMessage)
        }
    }

    private var usageSurface: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SystemFormat.percent(disk.usedFraction))
                        .font(.system(size: 42, weight: .semibold))
                        .tracking(-1.5)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())

                    Text("Disk used")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                StatRingGauge(
                    fraction: disk.usedFraction,
                    color: usageTint,
                    lineWidth: 9,
                    animation: animation
                )
                .frame(width: 70, height: 70)
                .overlay {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(usageTint)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(usageTint.opacity(0.16))
                    Capsule()
                        .fill(usageTint)
                        .frame(width: geometry.size.width * CGFloat(disk.usedFraction))
                        .animation(animation, value: disk.usedFraction)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(panelSurface)
    }

    private func capacityTile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(panelSurface)
    }

    private var storageInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.storageLargestItems)
                    .font(.system(size: 11, weight: .semibold))

                Spacer(minLength: 0)

                Button {
                    analyzer.scan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.pressScale)
                .disabled(analyzer.isScanning)
                .help(L10n.storageScanAgain)
            }

            if analyzer.isScanning && analyzer.items.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.storageScanning)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
            } else if analyzer.items.isEmpty {
                Text(analyzer.errorMessage ?? L10n.storageNoItems)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(analyzer.errorMessage == nil ? Color.secondary : SystemPalette.danger)
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else {
                VStack(spacing: 4) {
                    ForEach(analyzer.items.prefix(5)) { item in
                        storageRow(item)
                    }
                }
            }

            if let error = analyzer.errorMessage, !analyzer.items.isEmpty {
                Text(error)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(SystemPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func storageRow(_ item: StorageCandidate) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Text(item.parentName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(SystemFormat.bytes(item.allocatedSize))
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                analyzer.reveal(item)
            } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.storageRevealInFinder)

            if allowsDeletion {
                Button {
                    pendingDeletion = item
                } label: {
                    Group {
                        if analyzer.removingIDs.contains(item.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "trash")
                        }
                    }
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SystemPalette.danger.opacity(0.9))
                .disabled(analyzer.removingIDs.contains(item.id))
                .help(L10n.storageMoveToTrash)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { analyzer.reveal(item) }
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.98, anchor: .trailing))
        )
    }

    private var usageTint: Color {
        if disk.usedFraction >= 0.9 { return SystemPalette.danger }
        if disk.usedFraction >= 0.75 { return SystemPalette.warning }
        return SystemPalette.accent
    }
}

// MARK: - Panel primitives

private func panelHeader(
    symbol: String,
    title: String,
    subtitle: String? = nil,
    tint: Color
) -> some View {
    HStack(spacing: 10) {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.14))
            }

        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        Spacer(minLength: 0)
    }
}

private func compactPill(_ label: String, _ value: String, tint: Color? = nil) -> some View {
    HStack(spacing: 5) {
        if !label.isEmpty {
            Text(label)
                .foregroundStyle(.secondary)
        }
        Text(value)
            .foregroundStyle(tint ?? Color.primary)
            .monospacedDigit()
    }
    .font(.system(size: 10.5, weight: .semibold))
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background {
        Capsule().fill(Color.primary.opacity(0.065))
    }
}

private var panelSurface: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.055))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.055), lineWidth: 0.5)
        }
}

private func unavailablePanel(_ text: String, symbol: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: symbol)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.secondary)
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 120)
}

private struct CompactBatteryGauge: View {
    let fraction: Double
    let isCharging: Bool
    let animation: Animation?

    var body: some View {
        HStack(spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.55), lineWidth: 2)

                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .fill(isCharging ? SystemPalette.positive : SystemPalette.accent)
                        .frame(
                            width: max((geometry.size.width - 8) * CGFloat(min(max(fraction, 0), 1)), 4),
                            height: geometry.size.height - 8
                        )
                        .padding(4)
                        .animation(animation, value: fraction)

                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            Capsule()
                .fill(Color.secondary.opacity(0.55))
                .frame(width: 3, height: 12)
        }
        .accessibilityHidden(true)
    }
}

/// Tam ekran sistem kartlarının büyük tipografisini dar panele sıkıştırmak
/// yerine, ağın iki temel sorusunu sırayla cevaplayan kompakt görünüm:
/// “Şu an ne oluyor?” ve “Ne kadar veri kullandım?”.
struct PanelNetworkView: View {
    let network: NetworkStats
    let reduceMotion: Bool
    let animation: Animation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            liveRates

            StatDualBarChart(
                up: network.uploadHistory,
                down: network.downloadHistory,
                upColor: SystemPalette.accent,
                downColor: SystemPalette.secondary,
                height: 52,
                capacity: 34
            )

            Divider().opacity(0.25)

            usageSummary
            historyColumns
            StatBarChart(
                samples: network.dailyTotals.map(Double.init),
                normalizesToPeak: true,
                height: 52,
                capacity: 30
            )

            Text(L10n.networkHistoryHint)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(animation, value: network)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SystemPalette.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SystemPalette.secondary.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.networkActivityLabel)
                    .font(.system(size: 15, weight: .semibold))

                HStack(spacing: 5) {
                    Text(network.interfaceName.isEmpty ? "—" : network.interfaceName)

                    if !network.localAddress.isEmpty {
                        Text("•")
                        Text(network.localAddress)
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(network.interfaceName.isEmpty ? Color.secondary : SystemPalette.positive)
                .frame(width: 7, height: 7)
                .shadow(
                    color: (network.interfaceName.isEmpty ? Color.clear : SystemPalette.positive)
                        .opacity(0.45),
                    radius: 4
                )
                .accessibilityHidden(true)
        }
    }

    private var liveRates: some View {
        HStack(spacing: 8) {
            rateTile(
                label: L10n.networkDownloadLabel,
                value: SystemFormat.rate(network.downloadRate),
                symbolName: "arrow.down",
                color: SystemPalette.secondary
            )
            rateTile(
                label: L10n.networkUploadLabel,
                value: SystemFormat.rate(network.uploadRate),
                symbolName: "arrow.up",
                color: SystemPalette.accent
            )
        }
    }

    private func rateTile(
        label: String,
        value: String,
        symbolName: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.2)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
    }

    private var usageSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.networkTodayLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Text(SystemFormat.bytes(network.today))
                    .font(.system(size: 27, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.6)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }

            Spacer(minLength: 8)

            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var historyColumns: some View {
        HStack(alignment: .top, spacing: 8) {
            historyItem(L10n.networkYesterdayLabel, network.yesterday)
            historyItem(L10n.networkLast7DaysLabel, network.last7Days)
            historyItem(L10n.networkLast30DaysLabel, network.last30Days)
        }
    }

    private func historyItem(_ label: String, _ bytes: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(SystemFormat.bytes(bytes))
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Süreç bazlı ağ kullanımı

/// Activity Monitor'ün Ağ sekmesindeki listenin panele sığan hâli: en çok
/// harcayan beş süreç, indirme/gönderme kırılımıyla.
///
/// Tablo değil liste: dar panelde sütun başlıklarına ayıracak yer yok, üstelik
/// beş satır için başlık satırı taşımak da gereksiz. Bölüm katlanabilir ve
/// tercih kalıcı — kapalıyken ölçüm de durur, kimsenin bakmadığı bir liste
/// için dört saniyede bir süreç başlatmanın karşılığı yok.
struct PanelNetworkProcessList: View {
    let reduceMotion: Bool

    @State private var monitor = NetworkProcessMonitor.shared
    @AppStorage("panel.network.processesExpanded") private var isExpanded = true
    @State private var pendingQuit: NetworkProcessUsage?

    /// Reduce Motion açıkken yalnızca kısa bir sönümlenme kalıyor. Normalde
    /// kritik sönümlü yay: liste kendiliğinden güncelleniyor, kullanıcının
    /// taşıdığı bir momentum yok — taşma burada yalan olurdu.
    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.32, dampingFraction: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if isExpanded {
                content
                    .transition(.opacity)
            }
        }
        .animation(motion, value: isExpanded)
        .animation(motion, value: monitor.processes)
        .onAppear { if isExpanded { monitor.start() } }
        .onDisappear { if isExpanded { monitor.stop() } }
        .onChange(of: isExpanded) { _, expanded in
            if expanded { monitor.start() } else { monitor.stop() }
        }
        .alert(
            pendingQuit.map { L10n.networkProcessQuitPrompt(NetworkProcessPresentation(usage: $0).displayName) } ?? "",
            isPresented: Binding(
                get: { pendingQuit != nil },
                set: { if !$0 { pendingQuit = nil } }
            ),
            presenting: pendingQuit
        ) { usage in
            Button(L10n.cancel, role: .cancel) {
                pendingQuit = nil
            }
            Button(L10n.networkProcessQuit, role: .destructive) {
                pendingQuit = nil
                NetworkProcessPresentation(usage: usage).requestTermination()
            }
        } message: { _ in
            Text(L10n.networkProcessQuitMessage)
        }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Text(L10n.networkTopProcessesLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isExpanded, !monitor.processes.isEmpty {
                    Text("\(monitor.processes.count)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        if monitor.isUnavailable {
            note(L10n.networkProcessesUnavailable, symbolName: "exclamationmark.triangle")
        } else if !monitor.hasSampled {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.networkProcessesHint)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        } else if monitor.processes.isEmpty {
            note(L10n.networkProcessesEmpty, symbolName: "wifi.slash")
        } else {
            VStack(spacing: 3) {
                ForEach(monitor.processes) { usage in
                    PanelNetworkProcessRow(
                        usage: usage,
                        reduceMotion: reduceMotion,
                        onQuitRequested: { pendingQuit = usage }
                    )
                }
            }

            Text(L10n.networkProcessesHint)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Ölçüm alınamadığında ya da hiç trafik yokken gösterilen sakin satır.
    private func note(_ text: String, symbolName: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

/// Tek süreç satırı: ikon, ad, indirme/gönderme ve toplam. Sağdaki iki
/// düğme yalnızca kullanıcının kendi uygulamalarında etkin — arka plan
/// süreçleri ve GlassDo'nun kendisi görünür ama dokunulamaz.
private struct PanelNetworkProcessRow: View {
    let usage: NetworkProcessUsage
    let reduceMotion: Bool
    let onQuitRequested: () -> Void

    @State private var isHovering = false
    @State private var isQuitHovering = false

    var body: some View {
        let presentation = NetworkProcessPresentation(usage: usage)

        return HStack(spacing: 9) {
            icon(for: presentation)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    traffic(symbolName: "arrow.down", bytes: usage.bytesIn, color: SystemPalette.secondary)
                    traffic(symbolName: "arrow.up", bytes: usage.bytesOut, color: SystemPalette.accent)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(SystemFormat.bytes(usage.total))
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .lineLimit(1)

                controls(presentation)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.075 : 0.03))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(presentation.displayName), "
            + "\(L10n.networkDownloadLabel) \(SystemFormat.bytes(usage.bytesIn)), "
            + "\(L10n.networkUploadLabel) \(SystemFormat.bytes(usage.bytesOut))"
        )
    }

    @ViewBuilder
    private func icon(for presentation: NetworkProcessPresentation) -> some View {
        if let image = presentation.icon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
        } else {
            // Arka plan süreçlerinin ikonu yok. Boş bırakmak yerine nötr bir
            // rozet: satırların hizası bozulmasın.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func traffic(symbolName: String, bytes: UInt64, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)

            Text(SystemFormat.bytes(bytes))
                .font(.system(size: 10))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func controls(_ presentation: NetworkProcessPresentation) -> some View {
        let isControllable = presentation.isControllable

        return HStack(spacing: 7) {
            Button {
                presentation.activate()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(isControllable ? Color.secondary : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!isControllable)
            .help(L10n.networkProcessActivate)
            .accessibilityLabel(L10n.networkProcessActivate)

            Button {
                onQuitRequested()
            } label: {
                // Kapatma sessiz duruyor; yalnızca üzerine gelindiğinde
                // kırmızıya dönüyor. Rengi kaybolduğunda bile simge ve
                // erişilebilirlik etiketi yerinde kalıyor.
                Image(systemName: "xmark.circle")
                    .foregroundStyle(
                        isControllable
                            ? (isQuitHovering ? Color.red : Color.secondary)
                            : Color.secondary.opacity(0.4)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isControllable)
            .help(L10n.networkProcessQuit)
            .accessibilityLabel(L10n.networkProcessQuit)
            .onHover { isQuitHovering = $0 && isControllable }
        }
        .font(.system(size: 12, weight: .medium))
    }
}
