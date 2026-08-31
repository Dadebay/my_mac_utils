import SwiftUI

/// Widget'ların ortak paleti — ana penceredeki `SystemPalette` ile aynı
/// değerler. Uzantı ayrı bir süreç ve uygulamanın görünüm kodunu
/// derlemiyor; iki dosya arasında kopyalanan tek şey bu altı renk.
enum WidgetPalette {
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.92)
    static let secondary = Color(red: 0.29, green: 0.62, blue: 1.0)
    static let tertiary = Color(red: 0.31, green: 0.80, blue: 0.74)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let danger = Color(red: 0.94, green: 0.36, blue: 0.30)
    static let positive = Color(red: 0.34, green: 0.78, blue: 0.48)

    static let chartSurface = Color.primary.opacity(0.06)
}

/// Uzantı, uygulamanın `L10n`'ini (GlassDoKit) derlemiyor. Widget'ta
/// gösterilen metin bir avuç etiketten ibaret olduğu için dil, anlık
/// görüntüyle taşınan tercihten seçiliyor.
struct WidgetStrings {
    let language: String

    func callAsFunction(_ turkish: String, _ english: String, _ russian: String) -> String {
        switch language {
        case "tr": turkish
        case "ru": russian
        default: english
        }
    }
}

/// Widget'lar yeniden çizilirken animasyon yok; biçimlendiriciler de
/// tek örnek yeterli.
///
/// `ByteCountFormatter` Sendable değil; yalnızca görünümlerden (ana aktör)
/// çağrıldığı için tür ana aktöre bağlanıyor — uygulamadaki
/// `SystemFormat` ile aynı gerekçe.
@MainActor
enum WidgetFormat {
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

    /// Disk ve ağ ondalık (1000 tabanlı) sayılır — Finder ve üretici
    /// etiketleriyle aynı okuma.
    static func bytes(_ value: UInt64) -> String {
        decimal.string(fromByteCount: Int64(value))
    }

    /// Bellek ikili (1024) sayılır; RAM öyle üretiliyor.
    static func memoryBytes(_ value: UInt64) -> String {
        binary.string(fromByteCount: Int64(value))
    }

    static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        let value = max(fraction, 0) * 100
        return decimals == 0
            ? "\(Int(value.rounded()))%"
            : String(format: "%.\(decimals)f%%", value)
    }

    static func celsius(_ value: Double) -> String {
        "\(Int(value.rounded()))°C"
    }

    /// "74h", "3d 4h" — menü çubuğundaki gibi kısa.
    static func uptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        if hours < 48 { return "\(hours)h" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}

// MARK: - Başlık

/// Referans tasarımdaki kart başlığı: ince ikon + soluk başlık.
struct WidgetHeader: View {
    let symbolName: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .regular))
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Grafikler

/// Sabit sayıda yuvaya oturan çubuk grafiği. Veri yuvadan azsa sağ taraf
/// boş kalmaz — seri sona yaslanır, yani en yeni örnek hep sağda olur.
struct WidgetBarChart: View {
    var samples: [Double]
    var color: Color = WidgetPalette.accent
    /// Doluluk gibi dar aralıkta gezinen serilerde 0…1 ölçeği grafiği düz
    /// bir çizgiye çevirir; kendi tepesine ölçeklemek gerekir.
    var normalizesToPeak = false
    /// Sıcaklık gibi sabit bir bantta gezinen seriler için: verilirse
    /// `normalizesToPeak` yerine bu aralığa ölçeklenir.
    var valueRange: ClosedRange<Double>?
    var capacity: Int = 34

    var body: some View {
        GeometryReader { proxy in
            let slots = max(capacity, 1)
            let spacing = max(proxy.size.width / CGFloat(slots) * 0.22, 0.5)
            let barWidth = max((proxy.size.width - spacing * CGFloat(slots - 1)) / CGFloat(slots), 0.5)
            let peak = normalizesToPeak ? (samples.max() ?? 1) : 1
            let visible = Array(samples.suffix(slots))
            let leading = slots - visible.count

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<slots, id: \.self) { index in
                    let sample = index < leading ? 0 : visible[index - leading]
                    let fraction = fraction(for: sample, peak: peak)

                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(color.opacity(sample == 0 ? 0.18 : 1))
                        .frame(
                            width: barWidth,
                            height: max(proxy.size.height * fraction, 1.5)
                        )
                }
            }
            .frame(height: proxy.size.height, alignment: .bottom)
        }
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(WidgetPalette.chartSurface)
                .padding(-4)
        }
    }

    private func fraction(for sample: Double, peak: Double) -> Double {
        if let valueRange {
            let width = valueRange.upperBound - valueRange.lowerBound
            guard width > 0 else { return 0 }
            return min(max((sample - valueRange.lowerBound) / width, 0), 1)
        }
        return peak > 0 ? min(max(sample / peak, 0), 1) : 0
    }
}

/// Halka ölçer — bellek ve disk doluluğu için.
struct WidgetRing: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Batarya kartının zemininden yükselen dolgu — referans tasarımdaki gibi
/// kartın kendisi bir batarya gibi doluyor.
struct WidgetFillBackground: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(color.opacity(0.55))
                    .frame(height: proxy.size.height * min(max(fraction, 0), 1))
            }
        }
    }
}

extension WidgetStrings {
    /// Widget'ın **galeri** metinleri (ad, açıklama) kart çizilmeden önce,
    /// yani anlık görüntü okunmadan gerekiyor; orada sistemin dili
    /// kullanılıyor.
    static let system = WidgetStrings(
        language: Locale.current.language.languageCode?.identifier ?? "en"
    )
}

/// Termal baskının üç çubukla gösterimi — referans tasarımdaki gibi
/// derecenin yanında "ne kadar zorlanıyor" bilgisi.
struct WidgetThermalBars: View {
    var pressure: ThermalPressure

    private var level: Int {
        switch pressure {
        case .nominal: 1
        case .fair: 2
        case .serious: 3
        case .critical: 3
        }
    }

    private var color: Color {
        switch pressure {
        case .nominal: WidgetPalette.positive
        case .fair: WidgetPalette.warning
        case .serious, .critical: WidgetPalette.danger
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(1...3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                    .fill(index <= level ? color : color.opacity(0.22))
                    .frame(width: 2.5, height: CGFloat(index) * 3 + 2)
            }
        }
    }
}

extension ThermalPressure {
    func label(_ s: WidgetStrings) -> String {
        switch self {
        case .nominal: s("Normal", "Normal", "Норма")
        case .fair: s("Orta", "Fair", "Умеренно")
        case .serious: s("Yüksek", "High", "Высоко")
        case .critical: s("Kritik", "Critical", "Критично")
        }
    }
}

/// Çekirdek başına yük — widget'ın statik hâli.
///
/// Uzantı uygulamanın görünüm kodunu derlemiyor, bu yüzden `PerCoreLoadChart`
/// burada küçük bir kopya olarak duruyor. Animasyon yok: WidgetKit yeniden
/// çizerken ara kareleri çalıştırmıyor, anlık görüntü ne diyorsa o duruyor.
struct WidgetPerCoreChart: View {
    var usages: [Double]
    var color: Color = WidgetPalette.secondary

    var body: some View {
        GeometryReader { proxy in
            let count = max(usages.count, 1)
            let spacing = max(proxy.size.width / CGFloat(count) * 0.18, 0.5)
            let width = max((proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 0.5)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(usages.enumerated()), id: \.offset) { _, usage in
                    let clamped = min(max(usage, 0), 1)

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: width, height: proxy.size.height)
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(fill(for: clamped))
                                .frame(height: max(proxy.size.height * clamped, 1.5))
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
        }
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(WidgetPalette.chartSurface)
                .padding(-4)
        }
    }

    /// Uygulamadaki eşiklerle aynı: %80 dikkat, %95 uyarı.
    private func fill(for usage: Double) -> Color {
        if usage >= 0.95 { return WidgetPalette.danger }
        if usage >= 0.80 { return WidgetPalette.warning }
        return color
    }
}

/// En yoğun çekirdek, 1'den başlayan numarasıyla. Uygulamadaki
/// `PerCoreLoadChart.busiest(in:)` ile aynı kural.
enum WidgetCoreSummary {
    static func busiest(in usages: [Double]) -> (number: Int, usage: Double)? {
        guard let index = usages.indices.max(by: { usages[$0] < usages[$1] }) else { return nil }
        return (index + 1, usages[index])
    }
}
