import SwiftUI
import GlassDoKit

/// Menü çubuğundaki tek bir ölçerin çizimi.
///
/// Menü çubuğu dar ve yükseklik sabit (~22 pt): her ölçer ya tek satır
/// sayı, ya iki satır küçük sayı, ya da bir grafik. Renk kullanımı en aza
/// indirilmiş — menü çubuğu sistemin alanı, uygulamanın vitrini değil;
/// yalnızca uyarı eşiklerinde renk giriyor.
struct MenuBarItemView: View {
    let kind: MenuBarItemKind
    let snapshot: SystemSnapshot

    /// Menü çubuğunun kendi yüksekliği. Çizimler buna göre ölçekleniyor.
    static let height: CGFloat = 22

    var body: some View {
        content
            .frame(height: Self.height)
            .padding(.horizontal, 3)
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        // MARK: İşlemci
        case .cpuLoadBar:
            MenuBarGlyphGroup(letters: "CPU") {
                MenuBarFillBar(fraction: snapshot.cpu.usage, color: loadTint)
            }

        case .cpuLoadPercent:
            MenuBarGlyphGroup(letters: "CPU") {
                MenuBarValue(
                    text: SystemFormat.percent(snapshot.cpu.usage, decimals: 0),
                    reserving: MenuBarSample.percent
                )
            }

        case .cpuLoadChart:
            MenuBarGlyphGroup(letters: "CPU") {
                MenuBarChart(samples: snapshot.cpu.history, color: loadTint)
            }

        case .cpuTemperatureBar:
            MenuBarGlyphGroup(letters: "TMP") {
                MenuBarFillBar(fraction: temperatureFraction, color: temperatureTint)
            }

        case .cpuTemperatureValue:
            MenuBarValue(
                text: temperatureText,
                tint: temperatureTint,
                reserving: MenuBarSample.temperature
            )

        // MARK: Bellek
        case .memoryUsedBar:
            MenuBarGlyphGroup(letters: "MEM") {
                MenuBarFillBar(fraction: snapshot.memory.usedFraction, color: memoryTint)
            }

        case .memoryUsedBytes:
            MenuBarGlyphGroup(letters: "MEM") {
                MenuBarValue(
                    text: SystemFormat.memoryBytes(snapshot.memory.used),
                    reserving: memorySamples
                )
            }

        case .memoryUsedPercent:
            MenuBarGlyphGroup(letters: "MEM") {
                MenuBarValue(
                    text: SystemFormat.percent(snapshot.memory.usedFraction, decimals: 0),
                    reserving: MenuBarSample.percent
                )
            }

        case .memorySwapBytes:
            MenuBarGlyphGroup(letters: "SWP") {
                MenuBarValue(
                    text: SystemFormat.memoryBytes(snapshot.memory.swapUsed),
                    reserving: memorySamples
                )
            }

        case .memoryPressureChart:
            MenuBarGlyphGroup(letters: "MEM") {
                MenuBarChart(
                    samples: snapshot.memory.history.map { $0.reduce(0, +) },
                    color: memoryTint
                )
            }

        // MARK: Disk
        case .diskUsedBar:
            MenuBarGlyphGroup(letters: "SSD") {
                MenuBarFillBar(fraction: snapshot.disk.usedFraction, color: diskTint)
            }

        case .diskUsedRing:
            MenuBarRing(fraction: snapshot.disk.usedFraction, color: diskTint)

        case .diskUsedBytes:
            MenuBarValue(
                text: SystemFormat.bytes(snapshot.disk.used),
                reserving: MenuBarSample.bytes
            )

        case .diskUsedPercent:
            MenuBarGlyphGroup(letters: "SSD") {
                MenuBarValue(
                    text: SystemFormat.percent(snapshot.disk.usedFraction, decimals: 0),
                    reserving: MenuBarSample.percent
                )
            }

        case .diskFreeBytes:
            MenuBarValue(
                text: SystemFormat.bytes(snapshot.disk.free),
                reserving: MenuBarSample.bytes
            )

        // MARK: Ağ
        case .networkActivity:
            MenuBarGlyphGroup(letters: "NET") {
                MenuBarStackedValue(
                    top: MenuBarFormat.rate(snapshot.network.downloadRate),
                    bottom: MenuBarFormat.rate(snapshot.network.uploadRate),
                    reserving: MenuBarSample.rate
                )
            }

        case .networkDownload:
            MenuBarValue(
                text: "↓ " + MenuBarFormat.rate(snapshot.network.downloadRate),
                reserving: MenuBarSample.rate.map { "↓ " + $0 }
            )

        case .networkUpload:
            MenuBarValue(
                text: "↑ " + MenuBarFormat.rate(snapshot.network.uploadRate),
                reserving: MenuBarSample.rate.map { "↑ " + $0 }
            )

        case .networkArrows:
            MenuBarActivityArrows(
                download: snapshot.network.downloadRate,
                upload: snapshot.network.uploadRate
            )

        case .networkVPN:
            MenuBarBadge(text: "VPN", isActive: snapshot.network.isVPNActive)

        case .networkDataToday:
            MenuBarGlyphGroup(letters: "NET") {
                MenuBarValue(
                    text: SystemFormat.bytes(snapshot.network.today),
                    reserving: MenuBarSample.bytes
                )
            }

        // MARK: Batarya
        case .batteryLevelBar:
            MenuBarBatteryGlyph(
                fraction: Double(snapshot.battery.chargePercent) / 100,
                isCharging: snapshot.battery.isCharging,
                color: batteryTint
            )

        case .batteryPercent:
            MenuBarValue(
                text: snapshot.battery.isPresent ? "\(snapshot.battery.chargePercent)%" : "—",
                tint: batteryTint,
                reserving: MenuBarSample.percent
            )

        case .batteryPower:
            MenuBarValue(
                text: SystemFormat.decimals(snapshot.battery.power, 2, unit: "W"),
                reserving: MenuBarSample.power
            )

        case .batteryCycles:
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .medium))
                MenuBarValue(text: "\(snapshot.battery.cycleCount)", reserving: MenuBarSample.cycles)
            }

        case .batteryHealthPercent:
            HStack(spacing: 3) {
                Image(systemName: "cross.case")
                    .font(.system(size: 9, weight: .medium))
                MenuBarValue(
                    text: SystemFormat.percent(snapshot.battery.healthFraction, decimals: 0),
                    reserving: MenuBarSample.percent
                )
            }

        case .batteryTimeRemaining:
            MenuBarValue(text: remainingText, reserving: MenuBarSample.clock)

        // MARK: Makine
        case .deviceUptime:
            MenuBarValue(text: WidgetFormat.uptime(snapshot.device.uptime), reserving: MenuBarSample.uptime)
        }
    }

    /// Bellek ölçeri en çok toplam belleğe kadar çıkabildiği için yer
    /// ayırırken makinenin kendi büyüklüğü örnek alınıyor: 16 GB'lık bir
    /// Mac'te 930 GB'lık bir metne boşluk bırakmanın anlamı yok. Yüzde 99
    /// ve yirmide bir, biçimleyicinin hem "GB" hem "MB" yazdığı iki
    /// uzunluğu birden örnekliyor.
    private var memorySamples: [String] {
        let total: UInt64 = snapshot.memory.total > 0
            ? snapshot.memory.total
            : 16 * 1024 * 1024 * 1024
        return [
            SystemFormat.memoryBytes(total * 99 / 100),
            SystemFormat.memoryBytes(total / 20),
        ]
    }

    // MARK: - Eşikler

    private var loadTint: Color {
        snapshot.cpu.usage >= 0.85 ? SystemPalette.danger : .primary
    }

    private var memoryTint: Color {
        let value = snapshot.memory.pressureFraction
        if value >= 0.8 { return SystemPalette.danger }
        if value >= 0.6 { return SystemPalette.warning }
        return .primary
    }

    private var diskTint: Color {
        if snapshot.disk.usedFraction >= 0.9 { return SystemPalette.danger }
        if snapshot.disk.usedFraction >= 0.75 { return SystemPalette.warning }
        return .primary
    }

    private var batteryTint: Color {
        if snapshot.battery.isCharging { return SystemPalette.positive }
        if snapshot.battery.chargePercent <= 20 { return SystemPalette.danger }
        return .primary
    }

    private var temperatureTint: Color {
        guard let temperature = snapshot.cpu.temperature else { return .primary }
        if temperature >= 90 { return SystemPalette.danger }
        if temperature >= 70 { return SystemPalette.warning }
        return .primary
    }

    private var temperatureText: String {
        guard let temperature = snapshot.cpu.temperature else { return "—" }
        return "\(Int(temperature.rounded()))°"
    }

    /// Sıcaklık çubuğunun ölçeği 30–100 °C: bu aralığın dışına çıkan bir
    /// Mac zaten kendini kısıyor demektir.
    private var temperatureFraction: Double {
        guard let temperature = snapshot.cpu.temperature else { return 0 }
        return min(max((temperature - 30) / 70, 0), 1)
    }

    private var remainingText: String {
        guard snapshot.battery.isPresent else { return "—" }
        if snapshot.battery.isCharging { return "⚡︎" }
        guard let minutes = snapshot.battery.minutesRemaining else { return "—" }
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }
}

// MARK: - Biçim ve yer ayırma

/// Menü çubuğuna özel hız biçimi.
///
/// `SystemFormat.rate` saniyede bir kilobaytın altını "512 bytes/s" diye
/// yazıyor: hem bütün biçimlerin en genişi (ölçere kalıcı boşluk açtırır),
/// hem de boşta duran bir makinenin arka plan gürültüsünü menü çubuğunda
/// gereksiz ayrıntıyla gösterir. Burada kilobaytın altı "0 KB/s" — birim
/// adı yine biçimleyiciden geldiği için sistemin diline uyuyor.
@MainActor
private enum MenuBarFormat {
    private static let kilobytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.allowedUnits = .useKB
        return formatter
    }()

    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond, 0)
        guard value >= 1000 else { return kilobytes.string(fromByteCount: 0) + "/s" }
        return SystemFormat.rate(value)
    }
}

/// Ölçerlere yer ayırırken kullanılan örnek metinler.
///
/// Bayt biçimleyicisi büyüklüğe göre farklı uzunlukta metin üretiyor
/// ("999 MB", "9,99 GB", "99,9 GB"): her büyüklükten bir örnek veriliyor,
/// en genişi hangisiyse ölçer o genişlikte kalıyor. Örnekler elle
/// yazılmak yerine biçimleyicinin kendisinden geçiriliyor — ondalık
/// ayracı ve birim adı sistemin diline göre değişiyor.
@MainActor
private enum MenuBarSample {
    static let percent = ["100%"]
    static let temperature = ["100°"]
    static let power = ["99.99 W"]
    static let cycles = ["9999"]
    static let clock = ["12:34"]
    static let uptime = ["99d 23h"]

    static let bytes: [String] = [
        999_000, 9_990_000, 99_900_000, 999_000_000,
        9_990_000_000, 99_900_000_000, 999_000_000_000, 9_990_000_000_000,
    ].map { SystemFormat.bytes($0) }

    /// Hız için gigabit ötesine yer ayırmanın karşılığı yok: en geniş
    /// örnek saniyede birkaç yüz megabayt.
    static let rate: [String] = [
        1_000, 999_000, 9_990_000, 99_900_000, 999_000_000,
    ].map { MenuBarFormat.rate($0) }
}

// MARK: - Parçalar

/// Ölçerin ne olduğunu söyleyen üç harflik dikey etiket. Menü çubuğunda
/// ikon için yer yok, ama çıplak bir sayı da neyin sayısı olduğunu
/// söylemiyor — referans tasarımdaki çözüm.
private struct MenuBarGlyphGroup<Content: View>: View {
    let letters: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 3) {
            // 6.5pt/bold'da "E" gibi birden çok yatay çizgi taşıyan
            // harfler, ekran ölçeği düşükken (Retina olmayan ya da
            // küçültülmüş bir ekran görüntüsünde) bulanıklaşıp okunmaz
            // hâle geliyordu — 7pt/heavy aynı 22pt'lik yüksekliğe sığıp
            // her harfe biraz daha kalın, ayırt edilebilir bir çizgi
            // veriyor.
            VStack(spacing: -1.7) {
                ForEach(Array(letters), id: \.self) { letter in
                    Text(String(letter))
                        .font(.system(size: 7, weight: .heavy))
                }
            }
            // Menü çubuğu, altındaki masaüstü duvar kâğıdını şeffaf
            // gösteriyor — `.secondary`'nin düşük opaklığı koyu/açık
            // temanın ikisinde de, özellikle renkli bir duvar kâğıdının
            // üstünde harfleri neredeyse görünmez kılıyordu. `.primary`
            // zaten sistemin etiket rengine göre otomatik tema değiştiriyor;
            // yalnızca büyük sayıdan bir tık soluk kalması için opaklık
            // veriliyor.
            .foregroundStyle(.primary.opacity(0.82))

            content
        }
    }
}

private struct MenuBarValue: View {
    let text: String
    var tint: Color = .primary
    /// Bu alanın alabileceği en geniş metinler. Bkz. `MenuBarReservedText`.
    var reserving: [String] = []

    var body: some View {
        MenuBarReservedText(text: text, samples: reserving)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

/// Sayı değiştikçe ölçerin genişliği oynamasın diye, gerçek metnin yanında
/// o alanın alabileceği en geniş örnekler de gizli olarak duruyor.
///
/// `ZStack` en geniş çocuğuna göre boyutlandığı, `.hidden()` ise yer
/// kaplamayı sürdürdüğü için genişlik değerden bağımsız sabit kalıyor —
/// "8%" ile "100%", "9 KB/s" ile "43 KB/s" aynı yeri kaplıyor. Genişliği
/// AppKit ile ölçüp `frame(minWidth:)` vermeye üstünlüğü, ölçünün metnin
/// kendi yazı tipiyle birebir aynı olması; dil ya da yazı tipi değişince
/// de doğru kalıyor. Örneklerden hiçbirine sığmayan bir değer gelirse
/// (beklenmedik bir büyüklük) yığın büyüyor, metin kırpılmıyor.
private struct MenuBarReservedText: View {
    let text: String
    let samples: [String]

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                Text(sample).hidden()
            }
            Text(text)
        }
    }
}

/// İki satırlık sayı — indirme üstte, yükleme altta. Menü çubuğunda tek
/// satırda iki hız yan yana çok yer kaplıyor.
private struct MenuBarStackedValue: View {
    let top: String
    let bottom: String
    /// İki satır aynı örneklerle yer ayırıyor: hem ölçer sabit genişlikte
    /// kalıyor hem de iki hız birbiriyle hizalanıyor.
    var reserving: [String] = []

    var body: some View {
        VStack(alignment: .trailing, spacing: -1) {
            MenuBarReservedText(text: top, samples: reserving)
            MenuBarReservedText(text: bottom, samples: reserving)
        }
        .font(.system(size: 8.5, weight: .medium))
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// Dikey dolan çubuk: yüzdeyi okumadan da doluluk görünür.
private struct MenuBarFillBar: View {
    let fraction: Double
    var color: Color = .primary

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.primary.opacity(0.18))
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(height: max(14 * min(max(fraction, 0), 1), 1))
        }
        .frame(width: 6, height: 14)
    }
}

private struct MenuBarRing: View {
    let fraction: Double
    var color: Color = .primary

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 13, height: 13)
    }
}

/// Menü çubuğuna sığan en küçük grafik: 16 örnek, 26 pt genişlik.
private struct MenuBarChart: View {
    let samples: [Double]
    var color: Color = .primary

    private static let slots = 16

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<Self.slots, id: \.self) { index in
                let visible = Array(samples.suffix(Self.slots))
                let leading = Self.slots - visible.count
                let value = index < leading ? 0 : visible[index - leading]
                let fraction = min(max(value, 0), 1)

                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                    .fill(color.opacity(value == 0 ? 0.18 : 0.85))
                    .frame(width: 1, height: max(14 * fraction, 1))
            }
        }
        .frame(height: 14, alignment: .bottom)
    }
}

/// İki ok — trafik varken doluyor, yokken soluyor. Sayı okumadan
/// "bir şey oluyor mu" sorusuna cevap veriyor.
private struct MenuBarActivityArrows: View {
    let download: Double
    let upload: Double

    /// Saniyede 32 KB'ın altı, arka plan gürültüsü sayılıyor.
    private static let threshold: Double = 32 * 1024

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .foregroundStyle(download > Self.threshold ? AnyShapeStyle(SystemPalette.secondary) : AnyShapeStyle(.tertiary))
            Image(systemName: "arrowtriangle.up.fill")
                .foregroundStyle(upload > Self.threshold ? AnyShapeStyle(SystemPalette.accent) : AnyShapeStyle(.tertiary))
        }
        .font(.system(size: 6.5))
    }
}

private struct MenuBarBadge: View {
    let text: String
    let isActive: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .foregroundStyle(isActive ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.tertiary))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.primary.opacity(0.6) : Color.primary.opacity(0.22),
                        lineWidth: 1
                    )
            }
    }
}

/// Yatay batarya simgesi — sistemin kendi göstergesine benzesin diye
/// uçta bir de tırnak var.
private struct MenuBarBatteryGlyph: View {
    let fraction: Double
    let isCharging: Bool
    var color: Color = .primary

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color)
                    .frame(width: max(16 * min(max(fraction, 0), 1), 1))
                    .padding(1.5)

                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.primary)
                        .frame(width: 19)
                }
            }
            .frame(width: 19, height: 11)

            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color.primary.opacity(0.45))
                .frame(width: 1.5, height: 4)
        }
    }
}
