import SwiftUI
import WidgetKit

// MARK: - Disk

struct DiskWidgetView: View {
    let entry: SystemEntry
    /// Ayarlardaki önizleme galerisi widget bağlamı dışında çiziliyor;
    /// orada aile ortamdan gelmediği için elle veriliyor.
    var forcedFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { forcedFamily ?? environmentFamily }

    private var disk: DiskStats { entry.snapshot.disk }
    private var s: WidgetStrings { entry.strings }

    /// %90 üstü dolulukta macOS'un kendisi de sıkışmaya başlar.
    private var tint: Color {
        if disk.usedFraction >= 0.9 { return WidgetPalette.danger }
        if disk.usedFraction >= 0.75 { return WidgetPalette.warning }
        return WidgetPalette.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(symbolName: "internaldrive", title: s("Disk", "Disk", "Диск"))

            if family == .systemSmall {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WidgetFormat.percent(disk.usedFraction))
                            .font(.system(size: 26, weight: .semibold))
                            .monospacedDigit()
                        Text(WidgetFormat.bytes(disk.free))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(s("boş", "free", "свободно"))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    WidgetRing(fraction: disk.usedFraction, color: tint, lineWidth: 7)
                        .frame(width: 44, height: 44)
                }
                Spacer(minLength: 0)
            } else {
                // Disk doluluğu çok yavaş değişir; kendi tepesine
                // ölçeklenmezse grafik düz bir çizgi gibi görünürdü.
                WidgetBarChart(samples: disk.history, color: tint, normalizesToPeak: true)
                    .frame(maxHeight: .infinity)

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(WidgetFormat.percent(disk.usedFraction))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                    Text("\(WidgetFormat.bytes(disk.used)) / \(WidgetFormat.bytes(disk.total))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Ağ trafiği

struct NetworkWidgetView: View {
    let entry: SystemEntry
    /// Ayarlardaki önizleme galerisi widget bağlamı dışında çiziliyor;
    /// orada aile ortamdan gelmediği için elle veriliyor.
    var forcedFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { forcedFamily ?? environmentFamily }

    private var network: NetworkStats { entry.snapshot.network }
    private var s: WidgetStrings { entry.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(
                symbolName: "globe",
                title: s("Ağ Trafiği", "Network Data", "Сетевой трафик")
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(s("Bugün", "Today", "Сегодня"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(WidgetFormat.bytes(network.today))
                    .font(.system(size: family == .systemSmall ? 22 : 28, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if family == .systemSmall {
                column(s("Son 7 gün", "Last 7 days", "7 дней"), WidgetFormat.bytes(network.last7Days))
            } else {
                HStack(alignment: .top, spacing: 0) {
                    column(s("Dün", "Yesterday", "Вчера"), WidgetFormat.bytes(network.yesterday))
                    Spacer(minLength: 6)
                    column(s("Son 7 gün", "Last 7 days", "7 дней"), WidgetFormat.bytes(network.last7Days))
                    Spacer(minLength: 6)
                    column(s("Son 30 gün", "Last 30 days", "30 дней"), WidgetFormat.bytes(network.last30Days))
                }
            }
        }
    }

    private func column(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Batarya

struct BatteryWidgetView: View {
    let entry: SystemEntry
    /// Ayarlardaki önizleme galerisi widget bağlamı dışında çiziliyor;
    /// orada aile ortamdan gelmediği için elle veriliyor.
    var forcedFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { forcedFamily ?? environmentFamily }

    private var battery: BatteryStats { entry.snapshot.battery }
    private var s: WidgetStrings { entry.strings }

    private var fillColor: Color {
        if battery.isCharging { return WidgetPalette.positive }
        if battery.chargePercent <= 20 { return WidgetPalette.danger }
        return WidgetPalette.tertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(
                symbolName: battery.isCharging ? "battery.100percent.bolt" : "battery.100percent",
                title: s("Batarya", "Battery", "Батарея")
            )

            if battery.isPresent {
                Text("\(battery.chargePercent)%")
                    .font(.system(size: family == .systemSmall ? 34 : 40, weight: .bold))
                    .monospacedDigit()

                Text("\(battery.charge) / \(battery.currentCapacity) mAh")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer(minLength: 0)

                if family != .systemSmall {
                    HStack(spacing: 0) {
                        detail(
                            s("Sağlık", "Health", "Здоровье"),
                            WidgetFormat.percent(battery.healthFraction)
                        )
                        Spacer(minLength: 6)
                        detail(s("Döngü", "Cycles", "Циклы"), "\(battery.cycleCount)")
                        Spacer(minLength: 6)
                        detail(
                            s("Güç", "Power", "Мощность"),
                            String(format: "%.1f W", battery.power)
                        )
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(s("Batarya yok", "No battery", "Нет батареи"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .background(alignment: .bottom) {
            // Kartın kendisi bir batarya gibi doluyor — referans tasarımdaki
            // gibi yüzdeyi okumadan da doluluk görünür olsun.
            if battery.isPresent {
                WidgetFillBackground(
                    fraction: Double(battery.chargePercent) / 100,
                    color: fillColor
                )
                .padding(-40)
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Bellek

struct MemoryWidgetView: View {
    let entry: SystemEntry
    /// Ayarlardaki önizleme galerisi widget bağlamı dışında çiziliyor;
    /// orada aile ortamdan gelmediği için elle veriliyor.
    var forcedFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { forcedFamily ?? environmentFamily }

    private var memory: MemoryStats { entry.snapshot.memory }
    private var s: WidgetStrings { entry.strings }

    private var tint: Color {
        let value = memory.pressureFraction
        if value >= 0.8 { return WidgetPalette.danger }
        if value >= 0.6 { return WidgetPalette.warning }
        return WidgetPalette.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(symbolName: "memorychip", title: s("Bellek", "Memory", "Память"))

            Text(WidgetFormat.percent(memory.usedFraction, decimals: 1))
                .font(.system(size: family == .systemSmall ? 28 : 34, weight: .bold))
                .monospacedDigit()

            Text("\(WidgetFormat.memoryBytes(memory.used)) / \(WidgetFormat.memoryBytes(memory.total))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            if family == .systemSmall {
                HStack {
                    Spacer(minLength: 0)
                    WidgetRing(fraction: memory.usedFraction, color: tint, lineWidth: 7)
                        .frame(width: 38, height: 38)
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        legend(
                            s("Uygulama", "App", "Приложения"),
                            memory.active,
                            WidgetPalette.accent
                        )
                        legend(
                            s("Çekirdek", "Wired", "Системная"),
                            memory.wired,
                            WidgetPalette.secondary
                        )
                        legend(
                            s("Sıkıştırılmış", "Compressed", "Сжатая"),
                            memory.compressed,
                            WidgetPalette.tertiary
                        )
                    }

                    Spacer(minLength: 0)

                    WidgetRing(fraction: memory.usedFraction, color: tint, lineWidth: 8)
                        .frame(width: 48, height: 48)
                }
            }
        }
    }

    private func legend(_ label: String, _ bytes: UInt64, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(WidgetFormat.memoryBytes(bytes))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
        }
    }
}

// MARK: - İşlemci sıcaklığı

struct ProcessorWidgetView: View {
    let entry: SystemEntry
    /// Ayarlardaki önizleme galerisi widget bağlamı dışında çiziliyor;
    /// orada aile ortamdan gelmediği için elle veriliyor.
    var forcedFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { forcedFamily ?? environmentFamily }

    private var cpu: CPULoadStats { entry.snapshot.cpu }
    private var s: WidgetStrings { entry.strings }

    private var tint: Color {
        guard let temperature = cpu.temperature else { return WidgetPalette.accent }
        if temperature >= 90 { return WidgetPalette.danger }
        if temperature >= 70 { return WidgetPalette.warning }
        return WidgetPalette.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(
                symbolName: "cpu",
                title: s("İşlemci Sıcaklığı", "Processor Temperature", "Температура ЦП")
            )

            if family == .systemSmall {
                Text(temperatureText)
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    WidgetThermalBars(pressure: cpu.thermalPressure)
                    Text(cpu.thermalPressure.label(s))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(s("Yük", "Load", "Загрузка")) \(WidgetFormat.percent(cpu.usage))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                HStack(spacing: 8) {
                    Text(temperatureText)
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()

                    Spacer(minLength: 8)

                    WidgetThermalBars(pressure: cpu.thermalPressure)
                    Text(cpu.thermalPressure.label(s))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Sabit 35...95 °C aralığı: tepeye ölçeklenirse dar bir
                // seride bütün çubuklar neredeyse aynı boyda görünür.
                // Geçmiş yoksa CPU kullanımını derece gibi göstermek yerine
                // boş grafik çizilir.
                WidgetBarChart(
                    samples: cpu.temperatureHistory,
                    color: tint,
                    valueRange: 35...95
                )
                .frame(height: 48)
            }
        }
    }

    /// Sensör okunamayan makinelerde derece yerine yalnızca termal baskı
    /// gösteriliyor — uydurma bir sayı yazılmıyor.
    private var temperatureText: String {
        guard let temperature = cpu.temperature else { return "—" }
        return WidgetFormat.celsius(temperature)
    }
}
