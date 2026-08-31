import SwiftUI
import GlassDoKit

// MARK: - Ortak biçimlendirme

/// Ölçer kartlarının paylaştığı sayı biçimleri. Disk ve ağ ondalık (1000
/// tabanlı) sayılır — Finder ve üretici etiketleriyle aynı okuma. Bellek
/// ikili (1024) sayılır, çünkü RAM öyle üretilir ve Etkinlik İzleyicisi
/// de öyle gösterir.
///
/// `ByteCountFormatter` Sendable değil; yalnızca görünümlerden (ana aktör)
/// çağrıldığı için tür ana aktöre bağlanıyor.
@MainActor
enum SystemFormat {
    private static let decimal: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static let binary: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func bytes(_ value: UInt64) -> String {
        decimal.string(fromByteCount: Int64(value))
    }

    static func memoryBytes(_ value: UInt64) -> String {
        binary.string(fromByteCount: Int64(value))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        decimal.string(fromByteCount: Int64(max(bytesPerSecond, 0))) + "/s"
    }

    static func percent(_ fraction: Double, decimals: Int = 1) -> String {
        let value = max(fraction, 0) * 100
        return decimals == 0
            ? "\(Int(value.rounded()))%"
            : String(format: "%.\(decimals)f%%", value)
    }

    static func decimals(_ value: Double, _ places: Int, unit: String) -> String {
        String(format: "%.\(places)f %@", value, unit)
    }
}

// MARK: - Ağ

struct NetworkCard: View {
    let network: NetworkStats
    var reduceMotion = false
    var onOpenSettings: (() -> Void)?

    var body: some View {
        StatCard(
            symbolName: "globe",
            title: L10n.networkDataLabel,
            onOpenSettings: onOpenSettings
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.networkTodayLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    StatHeadline(
                        value: SystemFormat.bytes(network.today),
                        reduceMotion: reduceMotion
                    )
                }

                StatColumns(
                    items: [
                        .init(label: L10n.networkYesterdayLabel, value: SystemFormat.bytes(network.yesterday)),
                        .init(label: L10n.networkLast7DaysLabel, value: SystemFormat.bytes(network.last7Days)),
                        .init(label: L10n.networkLast30DaysLabel, value: SystemFormat.bytes(network.last30Days)),
                    ],
                    reduceMotion: reduceMotion
                )

                Text(L10n.networkHistoryHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Color.primary.opacity(0.08))

                // Günlük toplamların grafiği yerine: menü çubuğu
                // popover'ı dar, otuz günlük bir çubuk grafik burada zaten
                // okunmuyordu. Aynı hız testi bileşeni ana pencere ve kenar
                // panelindeki ağ sayfalarında da kullanılıyor — üçü aynı
                // tasarımı paylaşsın diye burada da o.
                SpeedTestSection(isCompact: true)
            }
        }
    }
}

/// Anlık hız ve bağlantı kimliği — günlük toplamlardan ayrı bir kart,
/// çünkü biri "ne kadar harcadım", diğeri "şu an ne oluyor" sorusuna
/// cevap veriyor.
struct NetworkActivityCard: View {
    let network: NetworkStats
    var reduceMotion = false
    var onOpenSettings: (() -> Void)?

    var body: some View {
        StatCard(
            symbolName: "antenna.radiowaves.left.and.right",
            title: L10n.networkActivityLabel,
            onOpenSettings: onOpenSettings
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.networkConnectionLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text(network.interfaceName.isEmpty ? "—" : network.interfaceName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)

                        if !network.localAddress.isEmpty {
                            Label(network.localAddress, systemImage: "network")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 6) {
                        rateRow(
                            symbolName: "arrowtriangle.down.fill",
                            value: SystemFormat.rate(network.downloadRate),
                            color: SystemPalette.secondary
                        )
                        rateRow(
                            symbolName: "arrowtriangle.up.fill",
                            value: SystemFormat.rate(network.uploadRate),
                            color: SystemPalette.accent
                        )
                    }
                }

                StatDualBarChart(
                    up: network.uploadHistory,
                    down: network.downloadHistory,
                    upColor: SystemPalette.accent,
                    downColor: SystemPalette.secondary
                )
            }
        }
    }

    private func rateRow(symbolName: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 10))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
        }
    }
}

// MARK: - Batarya

/// Şu anki şarj, sıcaklık ve elektriksel durum.
struct BatteryCard: View {
    let battery: BatteryStats
    var reduceMotion = false
    var animation: Animation?
    var onOpenSettings: (() -> Void)?

    var body: some View {
        StatCard(
            symbolName: "battery.100percent",
            title: L10n.batteryLabel,
            onOpenSettings: onOpenSettings
        ) {
            if battery.isPresent {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            StatHeadline(
                                value: "\(battery.chargePercent)%",
                                detail: "\(battery.charge) / \(battery.currentCapacity) mAh",
                                reduceMotion: reduceMotion
                            )

                            StatPillRow {
                                StatPill(
                                    label: L10n.batteryTemperatureLabel,
                                    value: SystemFormat.decimals(battery.temperature, 0, unit: "°C"),
                                    tint: temperatureTint,
                                    reduceMotion: reduceMotion
                                )

                                if let minutes = battery.minutesRemaining, !battery.isCharging {
                                    StatPill(
                                        label: "",
                                        value: L10n.batteryTimeRemaining(minutes),
                                        reduceMotion: reduceMotion
                                    )
                                }
                            }
                        }

                        Spacer(minLength: 0)

                        StatBatteryGauge(
                            fraction: Double(battery.chargePercent) / 100,
                            color: battery.isCharging ? SystemPalette.positive : SystemPalette.accent,
                            animation: animation
                        )
                        .frame(width: 62, height: 96)
                    }

                    StatColumns(
                        items: [
                            .init(
                                label: L10n.batteryPowerLabel,
                                value: SystemFormat.decimals(battery.power, 2, unit: "W")
                            ),
                            .init(
                                label: L10n.batteryAmperageLabel,
                                value: SystemFormat.decimals(battery.amperage, 2, unit: "A")
                            ),
                            .init(
                                label: L10n.batteryVoltageLabel,
                                value: SystemFormat.decimals(battery.voltage, 2, unit: "V")
                            ),
                        ],
                        reduceMotion: reduceMotion
                    )

                    adapterSection
                }
            } else {
                unavailable(L10n.batteryUnavailable, symbolName: "battery.slash")
            }
        }
    }

    private var adapterSection: some View {
        HStack(spacing: 7) {
            Image(systemName: battery.isAdapterConnected ? "powerplug.fill" : "powerplug")
                .font(.system(size: 11))
                .foregroundStyle(
                    battery.isAdapterConnected ? SystemPalette.positive : Color.secondary.opacity(0.65)
                )

            Text(L10n.batteryAdapterLabel)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(adapterStatus)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(
                    battery.isAdapterConnected ? Color.primary : Color.secondary.opacity(0.65)
                )
        }
    }

    private var adapterStatus: String {
        if battery.isCharging { return L10n.batteryChargingLabel }
        return battery.isAdapterConnected ? "—" : L10n.batteryAdapterDisconnected
    }

    /// Apple dizüstülerinde 35 °C üstü sıcaklık dikkat çekmeli, 45 °C üstü
    /// uyarı — eşikler batarya ömrü açısından anlamlı.
    private var temperatureTint: Color? {
        if battery.temperature >= 45 { return SystemPalette.danger }
        if battery.temperature >= 35 { return SystemPalette.warning }
        return nil
    }
}

/// Uzun vadeli sağlık — şu anki şarjdan ayrı kart, çünkü ikisi
/// karıştırıldığında "%98 dolu" ile "%98 sağlıklı" ayırt edilemiyor.
struct BatteryHealthCard: View {
    let battery: BatteryStats
    var reduceMotion = false
    var animation: Animation?
    var onOpenSettings: (() -> Void)?

    var body: some View {
        StatCard(
            symbolName: "heart.text.square",
            title: L10n.batteryHealthLabel,
            onOpenSettings: onOpenSettings
        ) {
            if battery.isPresent {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            StatHeadline(
                                value: SystemFormat.percent(battery.healthFraction, decimals: 0),
                                detail: "\(battery.currentCapacity) / \(battery.designCapacity) mAh",
                                reduceMotion: reduceMotion
                            )

                            StatPillRow {
                                StatPill(
                                    label: L10n.batteryCyclesLabel,
                                    value: "\(battery.cycleCount)",
                                    reduceMotion: reduceMotion
                                )
                                StatPill(
                                    label: L10n.batteryConditionLabel,
                                    value: conditionText,
                                    tint: conditionColor,
                                    reduceMotion: reduceMotion
                                )
                            }
                        }

                        Spacer(minLength: 0)

                        StatRingGauge(
                            fraction: battery.healthFraction,
                            color: conditionColor,
                            lineWidth: 14,
                            animation: animation
                        )
                        .frame(width: 86, height: 86)
                    }
                }
            } else {
                unavailable(L10n.batteryUnavailable, symbolName: "battery.slash")
            }
        }
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
        case .perfect, .good: SystemPalette.accent
        case .fair: SystemPalette.warning
        case .service: SystemPalette.danger
        }
    }
}

// MARK: - Bellek

struct MemoryCard: View {
    let memory: MemoryStats
    var reduceMotion = false
    var animation: Animation?
    var onOpenSettings: (() -> Void)?

    var body: some View {
        StatCard(
            symbolName: "memorychip",
            title: L10n.memoryLabel,
            onOpenSettings: onOpenSettings
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        StatHeadline(
                            value: SystemFormat.percent(memory.usedFraction),
                            detail: "\(SystemFormat.memoryBytes(memory.used)) / \(SystemFormat.memoryBytes(memory.total))",
                            reduceMotion: reduceMotion
                        )

                        StatPillRow {
                            StatPill(
                                label: L10n.memoryPressureLabel,
                                value: SystemFormat.percent(memory.pressureFraction, decimals: 0),
                                tint: pressureTint,
                                reduceMotion: reduceMotion
                            )
                            if memory.swapTotal > 0 {
                                StatPill(
                                    label: L10n.memorySwapLabel,
                                    value: SystemFormat.memoryBytes(memory.swapUsed),
                                    reduceMotion: reduceMotion
                                )
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    StatSegmentedRing(
                        segments: [
                            (Double(memory.active) / Double(max(memory.total, 1)), SystemPalette.accent),
                            (Double(memory.wired) / Double(max(memory.total, 1)), SystemPalette.secondary),
                            (Double(memory.compressed) / Double(max(memory.total, 1)), SystemPalette.tertiary),
                        ],
                        lineWidth: 14,
                        animation: animation
                    )
                    .frame(width: 86, height: 86)
                }

                StatLegend(
                    items: [
                        .init(
                            label: L10n.memoryActiveLabel,
                            value: legendValue(memory.active),
                            color: SystemPalette.accent
                        ),
                        .init(
                            label: L10n.memoryWiredLabel,
                            value: legendValue(memory.wired),
                            color: SystemPalette.secondary
                        ),
                        .init(
                            label: L10n.memoryCompressedLabel,
                            value: legendValue(memory.compressed),
                            color: SystemPalette.tertiary
                        ),
                    ],
                    reduceMotion: reduceMotion
                )

                StatStackedBarChart(
                    samples: memory.history,
                    colors: [SystemPalette.accent, SystemPalette.secondary, SystemPalette.tertiary]
                )
            }
        }
    }

    private func legendValue(_ bytes: UInt64) -> String {
        let share = Double(bytes) / Double(max(memory.total, 1))
        return "\(SystemFormat.percent(share, decimals: 0)) • \(SystemFormat.memoryBytes(bytes))"
    }

    /// Baskı %60'ı geçtiğinde sistem takas etmeye başlar, %80 üstü sıkışma.
    private var pressureTint: Color? {
        let value = memory.pressureFraction
        if value >= 0.8 { return SystemPalette.danger }
        if value >= 0.6 { return SystemPalette.warning }
        return nil
    }
}

// MARK: - Disk

struct DiskCard: View {
    let disk: DiskStats
    var reduceMotion = false
    var animation: Animation?
    var onOpenSettings: (() -> Void)?

    var body: some View {
        StatCard(
            symbolName: "internaldrive",
            title: L10n.diskLabel,
            onOpenSettings: onOpenSettings
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        StatHeadline(
                            value: SystemFormat.percent(disk.usedFraction),
                            detail: disk.volumeName.isEmpty ? nil : disk.volumeName,
                            reduceMotion: reduceMotion
                        )

                        // Disk doluluğu saatler içinde kıpırdamıyor —
                        // geçmiş grafiği burada okunacak bir şey
                        // taşımıyordu. Sorulan asıl soru zaten bu iki
                        // sayı: ne kadarı dolu, ne kadarı boş.
                        StatPillRow {
                            StatPill(
                                label: L10n.diskUsedLabel,
                                value: SystemFormat.bytes(disk.used),
                                tint: usageTint,
                                reduceMotion: reduceMotion
                            )
                            StatPill(
                                label: L10n.diskFreeLabel,
                                value: SystemFormat.bytes(disk.free),
                                reduceMotion: reduceMotion
                            )
                        }
                    }

                    Spacer(minLength: 0)

                    StatRingGauge(
                        fraction: disk.usedFraction,
                        color: usageTint,
                        lineWidth: 14,
                        animation: animation
                    )
                    .frame(width: 86, height: 86)
                }
            }
        }
    }

    /// %90 üstü dolulukta macOS'un kendisi de sıkışmaya başlar.
    private var usageTint: Color {
        if disk.usedFraction >= 0.9 { return SystemPalette.danger }
        if disk.usedFraction >= 0.75 { return SystemPalette.warning }
        return SystemPalette.accent
    }
}

// MARK: - İşlemci

struct ProcessorCard: View {
    let cpu: CPULoadStats
    var reduceMotion = false
    var onOpenSettings: (() -> Void)?

    var body: some View {
        StatCard(
            symbolName: "cpu",
            title: L10n.processorLoadLabel,
            onOpenSettings: onOpenSettings
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Diğer kartlarla aynı düzen: baskın sayı üstte, rozetler
                // hemen altında kendi akış satırında. Rozetlerin büyük
                // sayıyla aynı satırı paylaşması dar popover'da ikisini de
                // sıkıştırıyordu.
                VStack(alignment: .leading, spacing: 10) {
                    StatHeadline(
                        value: SystemFormat.percent(cpu.usage),
                        reduceMotion: reduceMotion
                    )

                    StatPillRow {
                        StatPill(
                            label: L10n.processorThermalLabel,
                            value: thermalText,
                            tint: thermalTint,
                            reduceMotion: reduceMotion
                        )
                        StatPill(
                            label: "",
                            value: L10n.processorCoreSummary(cpu.coreCount),
                            reduceMotion: reduceMotion
                        )
                    }
                }

                StatLegend(
                    items: [
                        .init(
                            label: L10n.processorUserLabel,
                            value: SystemFormat.percent(cpu.userUsage),
                            color: SystemPalette.accent
                        ),
                        .init(
                            label: L10n.processorSystemLabel,
                            value: SystemFormat.percent(cpu.systemUsage),
                            color: SystemPalette.secondary
                        ),
                    ],
                    reduceMotion: reduceMotion
                )

                if !cpu.perCoreUsage.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Text(L10n.processorCoreActivityLabel)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 4)

                            if let busiest = PerCoreLoadChart.busiest(in: cpu.perCoreUsage) {
                                Text(L10n.processorBusiestCore(busiest.number, busiest.usage))
                                    .font(.system(size: 11, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                    .contentTransition(reduceMotion ? .identity : .numericText())
                                    .lineLimit(1)
                            }
                        }

                        PerCoreLoadChart(
                            usages: cpu.perCoreUsage,
                            animation: reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1.0)
                        )
                    }
                }
            }
        }
    }

    private var thermalText: String {
        switch cpu.thermalPressure {
        case .nominal: L10n.thermalNominal
        case .fair: L10n.thermalFair
        case .serious: L10n.thermalSerious
        case .critical: L10n.thermalCritical
        }
    }

    private var thermalTint: Color? {
        switch cpu.thermalPressure {
        case .nominal: nil
        case .fair: SystemPalette.warning
        case .serious, .critical: SystemPalette.danger
        }
    }
}

// MARK: - Ortak boş durum

@ViewBuilder
func unavailable(_ message: String, symbolName: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: symbolName)
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(.tertiary)
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 26)
}
