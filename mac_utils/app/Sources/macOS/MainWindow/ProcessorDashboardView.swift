import GlassDoKit
import SwiftUI

/// "CPU ve Pil" sayfasının kendi panosu. Panelin tek sütunlu kartları
/// pencerenin genişliğini boşa harcadığı için burada eşit genişlikte iki
/// sütun var: solda işlemcinin seyri, sağda bataryanın sağlığı.
///
/// Ölçüm sahibi değil — değerleri `SystemMetricPage` veriyor. Böylece aynı
/// denetleyici hem panelde hem burada tek bir aboneliğe dayanıyor.
struct ProcessorDashboardView: View {
    let cpu: CPULoadStats
    let battery: BatteryStats
    let uptime: TimeInterval
    var reduceMotion: Bool = false
    var animation: Animation?

    var body: some View {
        // Sayfa üç ölçüde yaşıyor: çok geniş pencerede satır başına üç
        // kart, orta boyda iki, dar pencerede tek sütun. Sütun sayısını
        // kartın okunur genişliği belirliyor — üç sütunu korumak için
        // kartları ezmek, iki sütunda ferah durmaktan kötü.
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 16) {
                row3 { heroCard } middle: { statusCard } trailing: { distributionCard }
                if battery.isPresent {
                    row3 { coreUsageCard } middle: { batteryCard } trailing: { batteryHealthCard }
                } else {
                    coreUsageCard
                }
            }
            .frame(minWidth: 1180)

            VStack(spacing: 16) {
                row { heroCard } trailing: { statusCard }
                row { coreUsageCard } trailing: { distributionCard }
                if battery.isPresent {
                    row { batteryCard } trailing: { batteryHealthCard }
                }
            }
            .frame(minWidth: 720)

            VStack(spacing: 16) {
                heroCard
                statusCard
                coreUsageCard
                distributionCard
                if battery.isPresent {
                    batteryCard
                    batteryHealthCard
                }
            }
        }
        .animation(animation, value: cpu)
        .animation(animation, value: battery)
    }

    /// Bir satırdaki iki kart: eşit genişlikte **ve** eşit yükseklikte.
    /// Yükseklik eşitlenmezse kısa olan kart yarım kalmış gibi duruyor;
    /// `fixedSize` satırı en uzun kartın boyuna sabitliyor, `maxHeight` de
    /// diğerini o boya kadar uzatıyor.
    private func row<Leading: View, Trailing: View>(
        @ViewBuilder _ leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            leading().frame(maxWidth: .infinity, maxHeight: .infinity)
            trailing().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Üç kartlık satır — aynı kural.
    private func row3<Leading: View, Middle: View, Trailing: View>(
        @ViewBuilder _ leading: () -> Leading,
        @ViewBuilder middle: () -> Middle,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            leading().frame(maxWidth: .infinity, maxHeight: .infinity)
            middle().frame(maxWidth: .infinity, maxHeight: .infinity)
            trailing().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - İşlemci kartları

    /// Sayfanın ilk cümlesi bir sayı değil, bir yargı: kullanıcı önce
    /// "iyi mi, kötü mü" sorusunun yanıtını alıyor, sayılar arkasından
    /// geliyor.
    private var heroCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.processorPerformanceEyebrow)
                    .font(.app(size: 10, weight: .semibold))
                    .kerning(0.9)
                    .foregroundStyle(SystemPalette.accent)

                VStack(alignment: .leading, spacing: 5) {
                    Text(verdict.headline)
                        .font(.app(size: 22, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(verdict.body)
                        .font(.app(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Dar sütunda grafik ile halka yan yana sığmıyor; orada
                // yalnızca halka kalıyor. İkisi alt alta dizilince kart
                // uzuyor ve aynı sayı iki kez söyleniyordu.
                ViewThatFits(in: .horizontal) {
                    heroChartRow
                    heroRingOnly
                }
            }
        }
    }

    private var heroChartRow: some View {
        HStack(alignment: .center, spacing: 18) {
            chart
                .frame(height: 118)
                .frame(maxWidth: .infinity)

            totalUsageRing(diameter: 124, lineWidth: 10, valueSize: 21)
        }
        .frame(minWidth: 380)
    }

    private var heroRingOnly: some View {
        totalUsageRing(diameter: 104, lineWidth: 9, valueSize: 18)
            .frame(maxWidth: .infinity)
    }

    private var chart: some View {
        ProcessorAreaChart(
            samples: cpu.layeredHistory,
            colors: [SystemPalette.accent, SystemPalette.secondary],
            capacity: 40,
            reduceMotion: reduceMotion
        )
    }

    private func totalUsageRing(
        diameter: CGFloat, lineWidth: CGFloat, valueSize: CGFloat
    ) -> some View {
        ZStack {
            StatRingGauge(
                fraction: cpu.usage,
                color: SystemPalette.accent,
                lineWidth: lineWidth,
                animation: animation
            )
            VStack(spacing: 1) {
                Text(percent(cpu.usage))
                    .font(.app(size: valueSize, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                Text(L10n.processorTotalUsageLabel)
                    .font(.app(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: diameter, height: diameter)
    }

    /// Durum: termal, iki pay ve makinenin kendisiyle ilgili sabitler.
    private var statusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(thermalTint)
                        .frame(width: 7, height: 7)
                        .shadow(color: thermalTint.opacity(0.7), radius: 3)

                    Text(thermalText)
                        .font(.app(size: 13, weight: .semibold))

                    Spacer(minLength: 4)
                }

                VStack(spacing: 9) {
                    valueRow(L10n.processorUserLabel, percent(cpu.userUsage), dot: SystemPalette.accent)
                    valueRow(L10n.processorSystemLabel, percent(cpu.systemUsage), dot: SystemPalette.secondary)
                }

                Divider().opacity(0.3)

                VStack(spacing: 9) {
                    valueRow(L10n.processorCoresLabel, "\(cpu.coreCount)")
                    if let temperature = cpu.temperature {
                        valueRow(L10n.processorTemperatureLabel, String(format: "%.0f°C", temperature))
                    }
                    valueRow(L10n.processorUptimeLabel, uptimeText)
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// Çekirdek başına yük: zamanın seyri değil, tek bir anın çekirdekler
    /// arasındaki dağılımı.
    private var coreUsageCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader(
                    title: L10n.processorCoreUsageTitle,
                    subtitle: L10n.processorCoreUsageSubtitle,
                    trailing: cpu.perCoreUsage.isEmpty
                        ? nil
                        : L10n.processorCoreSummary(cpu.perCoreUsage.count)
                )

                if cpu.perCoreUsage.isEmpty {
                    Text("—")
                        .font(.app(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    // Sütun başına düşen genişlik yüzdeyi taşıyamıyorsa
                    // yazılar düşüyor: okunmayan 6 puntoluk bir sayı
                    // yazmaktansa hiç yazmamak doğru. Yükseklik iki durumda
                    // da aynı, yani kart ölçüme göre oynamıyor.
                    GeometryReader { geo in
                        let count = cpu.perCoreUsage.count
                        let spacing: CGFloat = 4
                        let perColumn = (geo.size.width - spacing * CGFloat(max(count - 1, 0)))
                            / CGFloat(max(count, 1))

                        HStack(alignment: .bottom, spacing: spacing) {
                            ForEach(Array(cpu.perCoreUsage.enumerated()), id: \.offset) { index, value in
                                coreColumn(index: index, value: value, showsLabel: perColumn >= 22)
                            }
                        }
                    }
                    .frame(height: 132)
                }
            }
        }
    }

    private func coreColumn(index: Int, value: Double, showsLabel: Bool) -> some View {
        VStack(spacing: showsLabel ? 6 : 0) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: coreColors(for: value),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        // En küçük yük de görünsün: sıfır yükseklikte bir
                        // sütun "ölçüm yok" gibi okunuyordu.
                        .frame(height: max(geo.size.height * clamped(value), 3))
                        .animation(animation, value: value)
                }
            }

            if showsLabel {
                Text("\(Int((value * 100).rounded()))%")
                    .font(.app(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(height: 11)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.processorPerCoreAccessibility(index + 1, value))
    }

    /// Sütunun rengi yükü de söylüyor: zorlanan çekirdek on beş sütunun
    /// içinde yalnızca boyuyla değil rengiyle de ayrılıyor.
    private func coreColors(for value: Double) -> [Color] {
        if value >= 0.85 { return [SystemPalette.danger, SystemPalette.danger.opacity(0.75)] }
        if value >= 0.6 { return [SystemPalette.warning, SystemPalette.warning.opacity(0.8)] }
        return [SystemPalette.secondary, SystemPalette.accent]
    }

    /// Kullanıcı / sistem / boşta payları. Toplam kullanım halkası zaten
    /// yukarıda; burada o toplamın neye gittiği var.
    private var distributionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader(
                    title: L10n.processorDistributionTitle,
                    subtitle: L10n.processorDistributionSubtitle,
                    trailing: nil
                )

                // Halka ile lejant dar sütunda yan yana sığmıyor; orada alt
                // alta geçiyorlar.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        distributionRing
                        distributionLegend
                    }
                    .frame(minWidth: 300)

                    VStack(alignment: .leading, spacing: 14) {
                        distributionRing.frame(maxWidth: .infinity)
                        distributionLegend
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var distributionRing: some View {
        StatSegmentedRing(
            segments: [
                (fraction: clamped(cpu.userUsage), color: SystemPalette.accent),
                (fraction: clamped(cpu.systemUsage), color: SystemPalette.secondary),
            ],
            lineWidth: 14,
            animation: animation
        )
        .frame(width: 112, height: 112)
    }

    private var distributionLegend: some View {
        VStack(alignment: .leading, spacing: 9) {
            valueRow(L10n.processorUserLabel, percent(cpu.userUsage), dot: SystemPalette.accent)
            valueRow(L10n.processorSystemLabel, percent(cpu.systemUsage), dot: SystemPalette.secondary)
            valueRow(
                L10n.processorIdleLabel,
                percent(max(0, 1 - cpu.userUsage - cpu.systemUsage)),
                dot: Color.primary.opacity(0.22)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Batarya kartları

    private var batteryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader(
                    title: L10n.batteryLabel,
                    subtitle: batteryStatusText,
                    trailing: battery.temperature > 0
                        ? String(format: "%.0f°C", battery.temperature)
                        : nil
                )

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(battery.chargePercent)%")
                        .font(.app(size: 34, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .identity : .numericText())

                    Text("\(battery.charge) / \(battery.currentCapacity) mAh")
                        .font(.app(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // Doluluk çubuğu yüzdeyi ikinci kez yazmak yerine
                // gösteriyor; şarj olurken rengi de değişiyor.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(batteryTint.opacity(0.16))
                        Capsule()
                            .fill(batteryTint)
                            .frame(
                                width: max(
                                    geo.size.width * CGFloat(battery.chargePercent) / 100,
                                    battery.chargePercent > 0 ? 4 : 0
                                )
                            )
                            .animation(animation, value: battery.chargePercent)
                    }
                }
                .frame(height: 6)

                Divider().opacity(0.3)

                VStack(spacing: 9) {
                    valueRow(L10n.batteryPowerLabel, String(format: "%.2f W", battery.power))
                    valueRow(L10n.batteryAmperageLabel, String(format: "%.2f A", battery.amperage))
                    valueRow(L10n.batteryVoltageLabel, String(format: "%.2f V", battery.voltage))
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var batteryHealthCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader(
                    title: L10n.batteryHealthLabel,
                    subtitle: conditionText,
                    trailing: nil
                )

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Sağlık ondalık basamağı hak etmiyor: haftalarca
                        // aynı sayıda duruyor, "100.0%" hem gereksiz hem de
                        // dar sütunda iki satıra bölünüyordu.
                        Text("\(Int((battery.healthFraction * 100).rounded()))%")
                            .font(.app(size: 34, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .contentTransition(reduceMotion ? .identity : .numericText())

                        Text("\(battery.currentCapacity) / \(battery.designCapacity) mAh")
                            .font(.app(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 8)

                    // Halka sağlığı gösteriyor, ortadaki simge durumu:
                    // yüzde tek başına "servis gerekli mi" sorusunu
                    // yanıtlamıyordu.
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 7)

                        Circle()
                            .trim(from: 0, to: max(battery.healthFraction, 0.001))
                            .stroke(conditionTint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(animation, value: battery.healthFraction)

                        Image(systemName: conditionSymbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(conditionTint)
                    }
                    .frame(width: 84, height: 84)
                }

                Divider().opacity(0.3)

                VStack(spacing: 9) {
                    valueRow(L10n.batteryCyclesLabel, "\(battery.cycleCount)")
                    valueRow(L10n.batteryConditionLabel, conditionText)
                    if let minutes = battery.minutesRemaining, minutes > 0 {
                        valueRow(L10n.batteryTimeLabel, L10n.batteryTimeRemaining(minutes))
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Ortak parçalar

    /// Kart gövdesi ortak kabukta: "Genel Bakış" sayfası da aynı yüzeyi
    /// kullanıyor (bkz. `dashboardCard()`).
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().dashboardCard()
    }

    private func cardHeader(title: String, subtitle: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.app(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func valueRow(_ label: String, _ value: String, dot: Color? = nil) -> some View {
        HStack(spacing: 8) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 7, height: 7)
            }

            Text(label)
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            // Sayı hiçbir koşulda kırpılmıyor: dar sütunda kısalması
            // gereken şey etiket, değer değil.
            Text(value)
                .font(.app(size: 12, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
    }

    // MARK: - Türetilen değerler

    /// Başlık ve açıklama tek yerde karar veriliyor: termal baskı her şeyin
    /// önünde, çünkü yavaşlamanın sebebi yük değil sıcaklık olabilir.
    private var verdict: (headline: String, body: String) {
        if cpu.thermalPressure == .serious || cpu.thermalPressure == .critical {
            return (L10n.processorHeadlineThermal, L10n.processorBodyThermal)
        }
        if cpu.usage >= 0.85 {
            return (L10n.processorHeadlineHeavy, L10n.processorBodyHeavy)
        }
        if cpu.usage >= 0.5 {
            return (L10n.processorHeadlineBusy, L10n.processorBodyBusy)
        }
        return (L10n.processorHeadlineCalm, L10n.processorBodyCalm)
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

    /// Üst satırda tek cümlede durum: şarj mı oluyor, adaptör takılı mı,
    /// yoksa bataryadan mı çalışıyor.
    private var batteryStatusText: String {
        if battery.isCharging { return L10n.batteryChargingLabel }
        if battery.isAdapterConnected { return L10n.batteryAdapterLabel }
        if let minutes = battery.minutesRemaining, minutes > 0 {
            return L10n.batteryTimeRemaining(minutes)
        }
        return L10n.batteryAdapterDisconnected
    }

    private var batteryTint: Color {
        if battery.isCharging { return SystemPalette.positive }
        if battery.chargePercent <= 10 { return SystemPalette.danger }
        if battery.chargePercent <= 20 { return SystemPalette.warning }
        return SystemPalette.accent
    }

    private var conditionText: String {
        switch battery.condition {
        case .perfect: L10n.batteryConditionPerfect
        case .good: L10n.batteryConditionGood
        case .fair: L10n.batteryConditionFair
        case .service: L10n.batteryConditionService
        }
    }

    private var conditionTint: Color {
        switch battery.condition {
        case .perfect, .good: SystemPalette.positive
        case .fair: SystemPalette.warning
        case .service: SystemPalette.danger
        }
    }

    private var conditionSymbol: String {
        switch battery.condition {
        case .perfect, .good: "checkmark"
        case .fair: "exclamationmark"
        case .service: "wrench.adjustable"
        }
    }

    /// "2g 14sa" — saniye bu ölçekte gürültü.
    private var uptimeText: String {
        let total = Int(uptime)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)\(L10n.dayShort) \(hours)\(L10n.hourShort)" }
        if hours > 0 { return "\(hours)\(L10n.hourShort) \(minutes)\(L10n.minuteShort)" }
        return "\(minutes)\(L10n.minuteShort)"
    }

    private func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", clamped(fraction) * 100)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - Etkinlik şeridi

/// İşlemci kullanımının son birkaç dakikası: kullanıcı payı altta, sistem
/// payı onun üstünde, ikisi de yumuşatılmış bir eğriyle.
///
/// Önceki hâli sabit %0–100 ölçeğindeydi. Boştaki bir Mac'te bütün seri
/// kutunun en altında iki kıl çizgiye sıkışıyor, geri kalan %85 boş
/// duruyordu — grafik hem çirkin hem bilgisizdi. Burada ölçek pencerenin
/// kendi tepesine göre büyüyüp küçülüyor ve o tepe sayıyla yazılıyor:
/// eğri her zaman kutuyu dolduruyor ama okuyan kişi neye baktığını
/// biliyor. Ölçek değişimi yaylı ve sönümlü, böylece yeni bir tepe
/// geldiğinde grafik zıplamıyor, yerine oturuyor.
struct ProcessorAreaChart: View {
    /// Her örnek için katman payları (0…1), en eskisi başta.
    let samples: [[Double]]
    let colors: [Color]
    /// Kaç örnek gösterilecek — fazlası baştan atılıyor.
    var capacity: Int = 40
    var reduceMotion: Bool = false

    var body: some View {
        let series = stacked()
        let scale = scaleMax(for: series)

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                grid(in: geo.size)

                // Üstteki katman (toplam) önce, altındaki onun üstüne:
                // iki alan üst üste binmiyor, iç içe okunuyor.
                ForEach(Array(series.enumerated().reversed()), id: \.offset) { index, values in
                    let color = colors.indices.contains(index) ? colors[index] : colors.last ?? .accentColor

                    ActivityArea(values: values, scaleMax: scale, closed: true)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.38), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    ActivityArea(values: values, scaleMax: scale, closed: false)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }

                // Şimdiki an: serinin ucundaki nokta. Sabit bir yerde
                // atmıyor — yalnızca ölçüm geldiğinde yerine oturuyor,
                // yani hareket veriyi anlatıyor, dikkat çekmiyor.
                if let head = headPoint(series, scale: scale, in: geo.size) {
                    Circle()
                        .fill(colors.first ?? .accentColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: (colors.first ?? .accentColor).opacity(0.8), radius: 4)
                        .position(head)
                }

                scaleLabel(scale)
            }
            // Geçmiş solda eriyor: kutunun kenarında kesilen bir eğri
            // "veri burada bitiyor" gibi okunuyordu.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 1.0),
            value: scale
        )
        .accessibilityHidden(true)
    }

    private func grid(in size: CGSize) -> some View {
        ForEach([0.0, 0.5, 1.0], id: \.self) { level in
            Path { path in
                let y = size.height * (1 - level)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    /// Ölçeğin tepesi. Grafiğin ne kadar "yüksek" göründüğü tek başına bir
    /// şey söylemiyor; bu yazı söylüyor.
    private func scaleLabel(_ scale: Double) -> some View {
        Text("\(Int((scale * 100).rounded()))%")
            .font(.app(size: 9, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .padding(.leading, 2)
            .padding(.top, 1)
    }

    /// Katmanları yığılmış toplamlara çevirir: [kullanıcı, kullanıcı+sistem].
    private func stacked() -> [[Double]] {
        let window = Array(samples.suffix(capacity))
        guard !window.isEmpty else { return [] }
        let layerCount = window.map(\.count).max() ?? 0
        guard layerCount > 0 else { return [] }

        return (0..<layerCount).map { layer in
            window.map { sample in
                min(max(sample.prefix(layer + 1).reduce(0, +), 0), 1)
            }
        }
    }

    /// Pencerenin tepesinin biraz üstü — eğri tavana yapışmasın. Alt sınır
    /// %15: boştaki bir makinede gürültü dağ gibi görünmemeli.
    private func scaleMax(for series: [[Double]]) -> Double {
        let peak = series.last?.max() ?? 0
        let padded = peak * 1.3
        // Beşer puanlık basamaklara yuvarlanıyor: her ölçümde kıpırdayan
        // bir ölçek okunamaz.
        let stepped = (padded / 0.05).rounded(.up) * 0.05
        return min(max(stepped, 0.15), 1)
    }

    private func headPoint(_ series: [[Double]], scale: Double, in size: CGSize) -> CGPoint? {
        guard let total = series.last, let last = total.last, total.count > 1 else { return nil }
        return CGPoint(
            x: size.width,
            y: size.height * (1 - min(last / scale, 1))
        )
    }
}

/// Noktaları orta noktalardan geçen ikinci derece eğrilerle bağlayan alan.
///
/// `Shape` olması ölçek değişiminin canlandırılabilmesi için: `animatableData`
/// ölçeğin kendisi, yani yeni bir tepe geldiğinde eğri yeni ölçeğe yaylanarak
/// geçiyor, bir karede zıplamıyor.
private struct ActivityArea: Shape {
    let values: [Double]
    var scaleMax: Double
    let closed: Bool

    var animatableData: Double {
        get { scaleMax }
        set { scaleMax = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            guard values.count > 1, scaleMax > 0 else { return }
            let step = rect.width / CGFloat(values.count - 1)

            func point(_ index: Int) -> CGPoint {
                let fraction = min(max(values[index] / scaleMax, 0), 1)
                return CGPoint(
                    x: CGFloat(index) * step,
                    y: rect.height * (1 - CGFloat(fraction))
                )
            }

            path.move(to: point(0))
            for index in 1..<values.count {
                let previous = point(index - 1)
                let current = point(index)
                let mid = CGPoint(
                    x: (previous.x + current.x) / 2,
                    y: (previous.y + current.y) / 2
                )
                path.addQuadCurve(to: mid, control: previous)
                if index == values.count - 1 {
                    path.addQuadCurve(to: current, control: current)
                }
            }

            if closed {
                path.addLine(to: CGPoint(x: rect.width, y: rect.height))
                path.addLine(to: CGPoint(x: 0, y: rect.height))
                path.closeSubpath()
            }
        }
    }
}
