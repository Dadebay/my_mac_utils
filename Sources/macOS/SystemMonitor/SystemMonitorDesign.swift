import SwiftUI
import GlassDoKit

// MARK: - Palet

/// Sistem ölçerlerinin ortak rengi. Mor birincil ölçüm, mavi ikincil,
/// turkuaz üçüncül — üç seri bir arada gösterildiğinde (bellek dökümü gibi)
/// birbirinden ayrılsın diye ton değil renk ayrımı kullanılıyor.
enum SystemPalette {
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.92)
    static let secondary = Color(red: 0.29, green: 0.62, blue: 1.0)
    static let tertiary = Color(red: 0.31, green: 0.80, blue: 0.74)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let danger = Color(red: 0.94, green: 0.36, blue: 0.30)
    static let positive = Color(red: 0.34, green: 0.78, blue: 0.48)

    /// Grafik zeminleri: kartın kendisinden biraz daha koyu bir yüzey.
    static let chartSurface = Color(red: 0.30, green: 0.27, blue: 0.55).opacity(0.16)
}

// MARK: - Kart kabuğu

/// Referans tasarımın kart düzeni: ince çizgili ikon + başlık, sağda ayar
/// düğmesi, altında içerik. Kartlar arası ayrım dolgu yerine ayraçla
/// yapılıyor — panoda yan yana dizildiklerinde tek bir yüzey gibi okunsun.
struct StatCard<Content: View>: View {
    let symbolName: String
    let title: String
    var onOpenSettings: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Spacer(minLength: 8)

                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.settingsTitle)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Baskın değer

/// Kartın tek baskın sayısı. Referanstaki gibi çok büyük ve sıkı aralıklı;
/// altındaki ikincil satır bağlamı taşır.
///
/// Kart ilk göründüğünde rakam sıfırdan gerçek değere doğru "sayarak"
/// geliyor — `.numericText()` geçişi zaten değer değiştiğinde rakamları
/// yuvarlayarak akıtıyordu (canlı ölçüm güncellemelerinde hâlâ öyle);
/// burada yalnızca İLK karede görüntülenen değeri sıfırlanmış bir yer
/// tutucuya çeviriyoruz ki `onAppear`'daki tek geçiş de aynı mekanizmayı
/// kullanarak sıfırdan saysın.
struct StatHeadline: View {
    let value: String
    var detail: String?
    var reduceMotion = false
    var size: CGFloat = 40
    /// Kartın kendisi mi, yoksa sayının anlamı mı ("son açılıştan beri
    /// geçen süre" gibi) sayma animasyonuna uygun değilse false verilir.
    var countsUpOnAppear = true

    @State private var displayedValue: String
    @State private var hasCountedUp = false

    init(value: String, detail: String? = nil, reduceMotion: Bool = false, size: CGFloat = 40, countsUpOnAppear: Bool = true) {
        self.value = value
        self.detail = detail
        self.reduceMotion = reduceMotion
        self.size = size
        self.countsUpOnAppear = countsUpOnAppear
        // İlk kare zaten sıfırlanmış değerle çiziliyor — `onAppear` bunu
        // gerçek değere animasyonla taşıyacak. Böylece aradaki gecikmeyi
        // gizlemek için yapay bir bekleme gerekmiyor.
        _displayedValue = State(initialValue: countsUpOnAppear && !reduceMotion ? Self.zeroed(value) : value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayedValue)
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .tracking(-1.0)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let detail {
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .onAppear {
            guard countsUpOnAppear, !reduceMotion, !hasCountedUp else { return }
            hasCountedUp = true
            withAnimation(.easeOut(duration: 0.9)) {
                displayedValue = value
            }
        }
        .onChange(of: value) { _, newValue in
            // Sayma bitmeden (ya da hiç başlamadan) gelen canlı ölçüm
            // güncellemeleri normal `numericText` rakam yuvarlamasını
            // kullanır — yalnızca ilk görünüş sıfırdan başlıyor.
            guard hasCountedUp || !countsUpOnAppear || reduceMotion else { return }
            displayedValue = newValue
        }
    }

    /// Aynı biçimin (ayraç, birim, yüzde işareti) sıfırlanmış hâli —
    /// yalnızca rakamlar "0" oluyor, geri kalan karakter aynı kalıyor ki
    /// sayarken düzen zıplamasın.
    private static func zeroed(_ value: String) -> String {
        String(value.map { $0.isNumber ? "0" : $0 })
    }
}

// MARK: - Rozet

/// "Temperature **30°C**" biçimindeki etiket+değer rozeti: etiket silik,
/// değer kalın — tek bakışta değer okunur, etiket gerektiğinde.
struct StatPill: View {
    let label: String
    let value: String
    var tint: Color?
    var reduceMotion = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .lineLimit(1)
        // Rozet asla kırpılmıyor ("Nor…" gibi okunaksız bir kesik yerine).
        // Sığmama sorununu satırın kendisi çözüyor: `StatPillRow` rozeti
        // alt satıra indiriyor.
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        }
    }
}

/// Rozet satırı: sığdığı kadarını yan yana dizer, sığmayanı alt satıra
/// indirir.
///
/// Düz bir `HStack` burada iki kötü seçenekten birine zorluyordu: ya
/// rozetler kırpılıyor ("Pressure 24%" → "Pres…"), ya da kırpılmayı
/// engellemek için sabitlenip satırın tamamını kartın dışına taşırıyorlardı.
/// Akış düzeni ikisini de yapmıyor: rozet her zaman tam okunuyor ve satır
/// hiçbir zaman verilen genişliği aşmıyor.
///
/// Genişlik sorgularına doğru cevap vermesi önemli: sıfır genişlik
/// önerildiğinde en geniş tek rozeti (gerçek asgari), sınırsız
/// önerildiğinde tek satırlık toplamı (ideal) bildiriyor — böylece yanındaki
/// göstergeyle aynı `HStack` içinde doğru pay alıyor.
struct StatPillRow<Content: View>: View {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        // `callAsFunction` açıkça yazılıyor: `PillFlowLayout() { … }` biçimi
        // Swift tarafından "init'e verilen sondaki kapanış" olarak da
        // okunabildiği için belirsiz kalıyor.
        PillFlowLayout(spacing: spacing, lineSpacing: lineSpacing)
            .callAsFunction { content }
    }
}

/// `GlassDoKit.Layout` (ölçü sabitleri) ile karışmasın diye nitelikli isim.
private struct PillFlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(for subviews: LayoutSubviews, maxWidth: CGFloat) -> [Line] {
        var result: [Line] = []
        var current = Line()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let candidateWidth = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width

            if !current.indices.isEmpty, candidateWidth > maxWidth {
                result.append(current)
                current = Line(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = candidateWidth
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { result.append(current) }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let lines = lines(for: subviews, maxWidth: proposal.width ?? .infinity)
        let height = lines.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout ()
    ) {
        var y = bounds.minY

        for line in lines(for: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }
}

// MARK: - Sütun satırı

/// Referanstaki "Power / Amperage / Voltage" üçlüsü: üstte silik etiket,
/// altında kalın değer, eşit genişlikte sütunlar.
struct StatColumns: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    let items: [Item]
    var reduceMotion = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(item.value)
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Gösterge açıklaması

/// Renkli nokta + etiket, altında yüzde ve mutlak değer.
struct StatLegend: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let color: Color
    }

    let items: [Item]
    var reduceMotion = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(item.color)
                            .frame(width: 7, height: 7)

                        Text(item.label)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                    }

                    Text(item.value)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Çubuk grafiği

/// Geçmiş serisi. Çizgi değil çubuk: örnekler ayrık zamanlarda alınıyor,
/// çizgi bunları sürekli bir sinyal gibi gösterip aradaki boşluğu
/// uydururdu.
struct StatBarChart: View {
    let samples: [Double]
    var color: Color = SystemPalette.accent
    /// Sabit tavan yoksa seri kendi en yükseğine göre ölçeklenir — yavaş
    /// değişen büyüklüklerde (disk gibi) fark görünür kalsın diye.
    var normalizesToPeak = false
    var height: CGFloat = 74
    /// Grafiğin kaç yuvası olduğu sabit; seri kısa olsa da düzen zıplamasın.
    var capacity: Int = 46

    private var normalized: [Double] {
        let visible = Array(samples.suffix(max(capacity, 1)))
        guard !visible.isEmpty else { return [] }
        guard normalizesToPeak else { return visible.map { min(max($0, 0), 1) } }

        let peak = visible.max() ?? 0
        guard peak > 0 else { return visible.map { _ in 0 } }
        // Tepe değeri tavana yapışmasın diye biraz pay bırakılıyor.
        return visible.map { min(max($0 / (peak * 1.1), 0), 1) }
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let width = max(
                (geo.size.width - spacing * CGFloat(capacity - 1)) / CGFloat(capacity), 1
            )

            // Seri sağ kenardan sola doğru akar: en yeni örnek hep aynı
            // yerde durur, geçmiş dolarken grafik sıçramaz.
            HStack(alignment: .bottom, spacing: spacing) {
                Spacer(minLength: 0)
                ForEach(Array(normalized.enumerated()), id: \.offset) { _, sample in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color)
                        .frame(width: width, height: max(geo.size.height * CGFloat(sample), 2))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
        }
        .frame(height: height)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SystemPalette.chartSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Birden çok seriyi üst üste yığan çubuk grafiği (bellek dökümü gibi).
struct StatStackedBarChart: View {
    /// Her örnek, toplamı 0…1 olan katman dilimleri.
    let samples: [[Double]]
    let colors: [Color]
    var height: CGFloat = 74
    var capacity: Int = 46

    var body: some View {
        let visibleSamples = Array(samples.suffix(max(capacity, 1)))

        GeometryReader { geo in
            let spacing: CGFloat = 2
            let width = max(
                (geo.size.width - spacing * CGFloat(capacity - 1)) / CGFloat(capacity), 1
            )

            HStack(alignment: .bottom, spacing: spacing) {
                Spacer(minLength: 0)
                ForEach(Array(visibleSamples.enumerated()), id: \.offset) { _, layers in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // En üstte son katman dursun diye ters sırayla dizilir.
                        ForEach(Array(layers.enumerated().reversed()), id: \.offset) { index, value in
                            Rectangle()
                                .fill(colors.indices.contains(index) ? colors[index] : SystemPalette.accent)
                                .frame(height: max(geo.size.height * CGFloat(min(max(value, 0), 1)), 0))
                        }
                    }
                    .frame(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
        }
        .frame(height: height)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SystemPalette.chartSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Sıfır çizgisinin iki yanına inen/çıkan trafiği ayıran grafik.
struct StatDualBarChart: View {
    let up: [Double]
    let down: [Double]
    var upColor: Color = SystemPalette.accent
    var downColor: Color = SystemPalette.secondary
    var height: CGFloat = 74
    var capacity: Int = 46

    private func scaled(_ series: [Double]) -> [Double] {
        let visibleUp = Array(up.suffix(max(capacity, 1)))
        let visibleDown = Array(down.suffix(max(capacity, 1)))
        let peak = max(visibleUp.max() ?? 0, visibleDown.max() ?? 0)
        let visible = Array(series.suffix(max(capacity, 1)))
        guard peak > 0 else { return visible.map { _ in 0 } }
        return visible.map { min(max($0 / (peak * 1.15), 0), 1) }
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let width = max(
                (geo.size.width - spacing * CGFloat(capacity - 1)) / CGFloat(capacity), 1
            )
            let half = geo.size.height / 2
            let upScaled = scaled(up)
            let downScaled = scaled(down)

            ZStack {
                // Sıfır çizgisi: iki yönün ayrımı görünür olsun.
                Rectangle()
                    .fill(downColor.opacity(0.45))
                    .frame(height: 1)

                HStack(alignment: .center, spacing: spacing) {
                    Spacer(minLength: 0)
                    ForEach(0..<max(upScaled.count, downScaled.count), id: \.self) { index in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(downColor)
                                .frame(height: max(half * CGFloat(downScaled.indices.contains(index) ? downScaled[index] : 0), 0))
                            Rectangle()
                                .fill(upColor)
                                .frame(height: max(half * CGFloat(upScaled.indices.contains(index) ? upScaled[index] : 0), 0))
                            Spacer(minLength: 0)
                        }
                        .frame(width: width, height: geo.size.height)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .frame(height: height)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SystemPalette.chartSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Göstergeler

/// Kalın halka. Tek bir oranı gösterirken kullanılır.
struct StatRingGauge: View {
    let fraction: Double
    var color: Color = SystemPalette.accent
    var lineWidth: CGFloat = 16
    var animation: Animation?

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(min(fraction, 1), 0.001))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                // Saat 12'den başlasın; varsayılan saat 3 yönü gösterge
                // olarak okunmuyor.
                .rotationEffect(.degrees(-90))
                .animation(animation, value: fraction)
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Birden çok dilimi tek halkada gösteren gösterge (bellek dökümü).
struct StatSegmentedRing: View {
    /// Her dilimin toplam içindeki payı, 0…1.
    let segments: [(fraction: Double, color: Color)]
    var lineWidth: CGFloat = 16
    var animation: Animation?

    var body: some View {
        ZStack {
            Circle()
                .stroke(SystemPalette.accent.opacity(0.16), lineWidth: lineWidth)

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let start = segments.prefix(index).reduce(0.0) { $0 + $1.fraction }
                Circle()
                    .trim(from: min(start, 1), to: min(start + segment.fraction, 1))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
        .animation(animation, value: segments.map(\.fraction))
        .accessibilityHidden(true)
    }
}

/// Referanstaki batarya biçimli gösterge — dolum yüksekliği şarj oranı.
struct StatBatteryGauge: View {
    let fraction: Double
    var color: Color = SystemPalette.accent
    var animation: Animation?

    var body: some View {
        GeometryReader { geo in
            let capWidth = geo.size.width * 0.34
            let capHeight: CGFloat = 5
            let bodyHeight = geo.size.height - capHeight

            VStack(spacing: 0) {
                // Uç kısım: batarya simgesi olduğu anlaşılsın diye.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color.opacity(0.35))
                    .frame(width: capWidth, height: capHeight)

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(color.opacity(0.18))

                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(color)
                        .frame(height: max(bodyHeight * CGFloat(min(max(fraction, 0), 1)), 3))
                        .animation(animation, value: fraction)
                }
                .frame(height: bodyHeight)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// Termometre biçimli gösterge — sıcaklık için.
struct StatThermometerGauge: View {
    /// Ölçek içindeki konum, 0…1.
    let fraction: Double
    var color: Color = SystemPalette.accent

    var body: some View {
        GeometryReader { geo in
            let bulb = geo.size.width * 0.62
            let stemWidth = geo.size.width * 0.22
            let stemHeight = geo.size.height - bulb

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(color.opacity(0.20))
                            .frame(width: stemWidth, height: stemHeight)
                        Capsule().fill(color)
                            .frame(
                                width: stemWidth,
                                height: max(stemHeight * CGFloat(min(max(fraction, 0), 1)), 2)
                            )
                    }
                    Circle()
                        .fill(color)
                        .frame(width: bulb, height: bulb)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Çekirdek başına yük

/// Her mantıksal çekirdeğin **o andaki** yükü, çekirdek başına bir sütun.
///
/// `StatBarChart` ile karıştırılmamalı: orada yatay eksen zamandır, burada
/// çekirdek sırası. İkisi alt alta durduğunda "ne zaman yüklendi" ile
/// "hangi çekirdek yüklü" birbirinden ayrılıyor — tek grafikle ikisi
/// birden okunamıyordu.
struct PerCoreLoadChart: View {
    /// 0…1 arası yükler, mantıksal çekirdek sırasında.
    let usages: [Double]
    var color: Color = SystemPalette.accent
    var height: CGFloat = 64
    /// Reduce Motion açıkken çağıran nil geçiyor.
    var animation: Animation? = .spring(response: 0.4, dampingFraction: 1.0)

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            // Sıfır çekirdek olamaz: bölmenin yanı sıra boş grafik de kendi
            // zeminini korumalı, düzen zıplamasın.
            let count = max(usages.count, 1)
            let width = max(
                (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count),
                1
            )

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(usages.enumerated()), id: \.offset) { _, usage in
                    let clamped = min(max(usage, 0), 1)

                    // Sabit track: dolgu düştüğünde sütunun yeri kaybolmuyor,
                    // göz çekirdek sırasını izlemeye devam ediyor.
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                        .frame(width: width, height: geo.size.height)
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(Self.fill(for: clamped, base: color))
                                .frame(height: max(geo.size.height * CGFloat(clamped), 2))
                        }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            .animation(animation, value: usages)
        }
        .frame(height: height)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SystemPalette.chartSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Otuz sütunu tek tek dinletmenin kimseye faydası yok; grafiğin
        // taşıdığı bilgi "hangi çekirdek en yüklü".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// %80 üstü dikkat, %95 üstü uyarı. Renk yalnızca sıkışmayı gösteriyor —
    /// her çekirdeğe ayrı renk vermek sütunları birbirinden ayırmaz, yalnızca
    /// grafiği okunmaz yapardı.
    static func fill(for usage: Double, base: Color) -> Color {
        if usage >= 0.95 { return SystemPalette.danger }
        if usage >= 0.80 { return SystemPalette.warning }
        return base
    }

    /// En yoğun çekirdek, kullanıcıya 1'den başlayan numarasıyla.
    static func busiest(in usages: [Double]) -> (number: Int, usage: Double)? {
        guard let index = usages.indices.max(by: { usages[$0] < usages[$1] }) else { return nil }
        return (index + 1, usages[index])
    }

    private var accessibilityText: String {
        guard let busiest = Self.busiest(in: usages) else { return L10n.processorCoreActivityLabel }
        return L10n.processorPerCoreAccessibility(busiest.number, busiest.usage)
    }
}
