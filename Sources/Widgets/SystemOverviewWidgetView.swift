import SwiftUI
import WidgetKit

/// Büyük masaüstü widget'ı. Her kart tek soruyu cevaplar; bütün kartlar aynı
/// ölçü, köşe ve tipografi sistemini paylaşır. Veri uygulamanın ortak
/// `SystemSnapshot` akışından gelir, bu yüzden ayrı bir ölçüm işi başlatmaz.
struct SystemOverviewWidgetView: View {
    let entry: SystemEntry

    private var snapshot: SystemSnapshot { entry.snapshot }
    private var s: WidgetStrings { entry.strings }

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 8
            let columnWidth = max((geometry.size.width - gap) / 2, 0)
            // Üç satırı da eşit yükseklikte tut; aksi halde son satır kırpılır.
            let rowHeight = max((geometry.size.height - gap * 2) / 3, 0)

            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                GridRow {
                    networkCard.frame(width: columnWidth, height: rowHeight)
                    batteryCard.frame(width: columnWidth, height: rowHeight)
                }
                .frame(height: rowHeight)

                GridRow {
                    diskCard.frame(width: columnWidth, height: rowHeight)
                    processorCard.frame(width: columnWidth, height: rowHeight)
                }
                .frame(height: rowHeight)

                GridRow {
                    memoryCard.frame(width: columnWidth, height: rowHeight)
                    systemCard.frame(width: columnWidth, height: rowHeight)
                }
                .frame(height: rowHeight)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private var networkCard: some View {
        overviewCard(symbol: "globe", title: s("Ağ Verisi", "Network Data", "Сетевые данные")) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s("Bugün", "Today", "Сегодня"))
                    .overviewCaption()
                Text(WidgetFormat.bytes(snapshot.network.today))
                    .overviewValue(size: 23)
            }

            Spacer(minLength: 1)

            HStack(spacing: 8) {
                overviewDetail(
                    s("Son 7 gün", "Last 7 days", "7 дней"),
                    WidgetFormat.bytes(snapshot.network.last7Days)
                )
                overviewDetail(
                    s("Son 30 gün", "Last 30 days", "30 дней"),
                    WidgetFormat.bytes(snapshot.network.last30Days)
                )
            }
        }
    }

    private var batteryCard: some View {
        overviewCard(
            symbol: snapshot.battery.isCharging ? "battery.100percent.bolt" : "battery.100percent",
            title: s("Batarya Sağlığı", "Battery Health", "Состояние батареи")
        ) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(WidgetFormat.percent(snapshot.battery.healthFraction))
                        .overviewValue(size: 27)
                    Text("\(snapshot.battery.currentCapacity) / \(snapshot.battery.designCapacity) mAh")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)

                WidgetRing(
                    fraction: snapshot.battery.healthFraction,
                    color: batteryTint,
                    lineWidth: 7
                )
                .frame(width: 42, height: 42)
            }

            Spacer(minLength: 1)

            HStack(spacing: 6) {
                overviewChip(symbol: "arrow.triangle.2.circlepath", value: "\(snapshot.battery.cycleCount)")
                overviewChip(symbol: "battery.75percent", value: batteryCondition)
            }
        }
    }

    private var diskCard: some View {
        overviewCard(symbol: "internaldrive", title: s("Disk", "Disk", "Диск")) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(WidgetFormat.percent(snapshot.disk.usedFraction, decimals: 1))
                        .overviewValue(size: 25)
                    Text(WidgetFormat.bytes(snapshot.disk.used))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text(WidgetFormat.bytes(snapshot.disk.total))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Spacer(minLength: 0)

                WidgetRing(fraction: snapshot.disk.usedFraction, color: diskTint, lineWidth: 7)
                    .frame(width: 44, height: 44)
            }

            Spacer(minLength: 1)

            Text(snapshot.disk.volumeName.isEmpty ? "Macintosh HD" : snapshot.disk.volumeName)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
    }

    private var processorCard: some View {
        overviewCard(symbol: "cpu", title: s("İşlemci Yükü", "Processor Load", "Загрузка процессора")) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(WidgetFormat.percent(snapshot.cpu.usage, decimals: 1))
                    .overviewValue(size: 25)

                Spacer(minLength: 0)

                if let busiest = WidgetCoreSummary.busiest(in: snapshot.cpu.perCoreUsage) {
                    let percent = Int((max(busiest.usage, 0) * 100).rounded())
                    Text(s(
                        "Çek. \(busiest.number) • %\(percent)",
                        "Core \(busiest.number) • \(percent)%",
                        "Ядро \(busiest.number) • \(percent)%"
                    ))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 1)

            // Eski anlık görüntüde çekirdek dökümü yok; o dosyalar için
            // zaman geçmişi grafiği duruyor.
            if snapshot.cpu.perCoreUsage.isEmpty {
                WidgetBarChart(
                    samples: snapshot.cpu.history,
                    color: WidgetPalette.secondary,
                    capacity: 18
                )
                .frame(height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                WidgetPerCoreChart(usages: snapshot.cpu.perCoreUsage)
                    .frame(height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }

    private var memoryCard: some View {
        overviewCard(symbol: "memorychip", title: s("Bellek", "Memory", "Память")) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(WidgetFormat.percent(snapshot.memory.usedFraction, decimals: 1))
                        .overviewValue(size: 25)
                    Text("\(WidgetFormat.memoryBytes(snapshot.memory.used)) / \(WidgetFormat.memoryBytes(snapshot.memory.total))")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)

                WidgetRing(
                    fraction: snapshot.memory.usedFraction,
                    color: memoryTint,
                    lineWidth: 7
                )
                .frame(width: 42, height: 42)
            }

            Spacer(minLength: 1)

            HStack(spacing: 5) {
                legendDot(WidgetPalette.accent, snapshot.memory.active)
                legendDot(WidgetPalette.secondary, snapshot.memory.wired)
                legendDot(WidgetPalette.tertiary, snapshot.memory.compressed)
            }
        }
    }

    private var systemCard: some View {
        overviewCard(symbol: "macbook", title: s("Sistem", "System", "Система")) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s("Çalışma süresi", "Uptime", "Время работы"))
                        .overviewCaption()
                    Text(WidgetFormat.uptime(snapshot.device.uptime))
                        .overviewValue(size: 23)
                }

                Spacer(minLength: 4)

                Circle()
                    .fill(entry.snapshot.isStale ? WidgetPalette.warning : WidgetPalette.positive)
                    .frame(width: 7, height: 7)
            }

            Spacer(minLength: 1)

            HStack(spacing: 5) {
                Image(systemName: entry.snapshot.isStale ? "clock.badge.exclamationmark" : "checkmark.circle.fill")
                    .foregroundStyle(entry.snapshot.isStale ? WidgetPalette.warning : WidgetPalette.positive)
                Text(entry.snapshot.isStale
                     ? s("Güncelleme bekleniyor", "Waiting for update", "Ожидание обновления")
                     : s("Canlı ölçümler", "Live measurements", "Актуальные данные"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func overviewCard<Content: View>(
        symbol: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(symbolName: symbol, title: title)
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                }
        }
        // İçerik hücre dışına taşarsa da görünür kalmasın.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func overviewDetail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).overviewCaption()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func overviewChip(symbol: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(value).lineLimit(1)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func legendDot(_ color: Color, _ bytes: UInt64) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(WidgetFormat.memoryBytes(bytes))
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private var diskTint: Color {
        if snapshot.disk.usedFraction >= 0.9 { return WidgetPalette.danger }
        if snapshot.disk.usedFraction >= 0.75 { return WidgetPalette.warning }
        return WidgetPalette.accent
    }

    private var memoryTint: Color {
        if snapshot.memory.pressureFraction >= 0.8 { return WidgetPalette.danger }
        if snapshot.memory.pressureFraction >= 0.6 { return WidgetPalette.warning }
        return WidgetPalette.accent
    }

    private var batteryTint: Color {
        switch snapshot.battery.condition {
        case .perfect, .good: WidgetPalette.positive
        case .fair: WidgetPalette.warning
        case .service: WidgetPalette.danger
        }
    }

    private var batteryCondition: String {
        switch snapshot.battery.condition {
        case .perfect: s("Mükemmel", "Perfect", "Отличное")
        case .good: s("İyi", "Good", "Хорошее")
        case .fair: s("Orta", "Fair", "Среднее")
        case .service: s("Servis", "Service", "Сервис")
        }
    }
}

private extension Text {
    func overviewCaption() -> some View {
        font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
    }

    func overviewValue(size: CGFloat) -> some View {
        font(.system(size: size, weight: .semibold))
            .tracking(-0.6)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }
}
