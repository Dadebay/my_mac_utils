import SwiftUI

/// Noktalı "düşünen küre" yükleniyor göstergesi.
///
/// Geometri, Jakub Antalik'in `thinking-orbs` kitaplığındaki **orbits**
/// ("working") kipinin birebir portu — kitaplık zaten kendi çekirdeğini
/// "her değeri kesinleşmiş, yeniden yorumlanmayacak çizim listesi" olarak
/// tasarlamış ve Swift portunu öngörmüş, bu yüzden burada yeniden
/// türetilen hiçbir sayı yok: aynı karma (hash), aynı izdüşüm, aynı
/// sıralama.
///
/// Kaynak: https://github.com/Jakubantalik/thinking-orbs (MIT, © 2026
/// Jakub Antalik). Kitaplığın kendisi bir npm paketi; bu uygulama SwiftUI
/// olduğu için paket kullanılamıyor, matematiği taşındı.
///
/// Neden sistemin `ProgressView`'ı değil: bekleme uygulamanın her yerinde
/// aynı görünsün diye. Dönen çubuk her yüzeyde farklı boyda duruyordu ve
/// panelin kendi diline hiç benzemiyordu.
public struct ThinkingOrbView: View {
    /// Kürenin kenarı (pt). Kitaplığın iki hazır ayarı var — 64 ve 20;
    /// aradaki boylarda yakın olanın sayıları kullanılıyor.
    public var size: CGFloat
    /// Erişilebilirlik etiketi; nil ise gösterge dekoratif sayılıyor.
    public var label: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat = 28, label: String? = nil) {
        self.size = size
        self.label = label
    }

    public var body: some View {
        Group {
            if reduceMotion {
                // Hareket azaltmada tek bir durağan kare: küre yine
                // "bekleniyor" diyor, ama dönmüyor.
                Canvas { context, _ in draw(in: &context, time: 0) }
            } else {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, _ in draw(in: &context, time: time) }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }

    private func draw(in context: inout GraphicsContext, time: TimeInterval) {
        let preset = OrbPreset.forSize(size)
        let dots = OrbGeometry.orbitsFrame(
            size: size,
            t: time * preset.speed,
            preset: preset
        )
        let isDark = colorScheme == .dark
        for dot in dots {
            // Mürekkep değeri koyu zeminde aynalanıyor: yakın noktalar
            // parlak okunuyor, uzaklar zemine gömülüyor.
            let ink = min(1, max(0, dot.white))
            let gray = isDark ? 1 - ink : ink
            let rect = CGRect(
                x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Color(white: gray, opacity: dot.alpha))
            )
        }
    }
}

// MARK: - Hazır ayarlar

/// Kitaplığın `PRESETS.orbits` satırları. `count` sayıları, `radius`
/// yarıçapları, `speed` ortak saati çarpıyor.
struct OrbPreset {
    let speed: Double
    let orbitN: Int
    let ghostN: Int
    let particles: Int
    let ghostR: Double
    let ghostA: Double
    let partR: Double
    let partRDepth: Double

    static let large = make(speed: 1.885, count: 1, radius: 1)
    static let small = make(speed: 3.9, count: 0.238, radius: 2.4)

    /// 64 ve 20 pt arasındaki sınır, iki hazır ayarın ortası.
    static func forSize(_ size: CGFloat) -> OrbPreset {
        size >= 42 ? large : small
    }

    /// `scaleCounts` / `scaleRadii`: sayılar doğrusal, yarıçaplar doğrudan
    /// çarpılıyor. `particles` kitaplıkta da ölçeklenmiyor — tek başına
    /// kalan parçacık hareketi taşıyan şey.
    private static func make(speed: Double, count: Double, radius: Double) -> OrbPreset {
        OrbPreset(
            speed: speed,
            orbitN: max(1, Int((12 * count).rounded())),
            ghostN: max(1, Int((40 * count).rounded())),
            particles: 3,
            ghostR: 0.9 * radius,
            ghostA: 0.5,
            partR: 1.2 * radius,
            partRDepth: 1.6 * radius
        )
    }
}

// MARK: - Geometri

/// Tek bir anın çizim listesi. Kitaplıktaki `Dot` ile aynı alanlar.
struct OrbDot {
    let x: CGFloat
    let y: CGFloat
    let z: Double
    let r: CGFloat
    /// 0 = en koyu mürekkep. Koyu zeminde aynalanıyor.
    let white: Double
    let alpha: Double
}

enum OrbGeometry {
    /// En küçük yarıçap: bunun altındaki nokta ekranda kayboluyor.
    private static let rMin: Double = 0.3

    /// Deterministik karma, [0, 1).
    private static func hashD(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - h.rounded(.down)
    }

    /// Nokta yarıçapları 300 pt'lik bir çerçeve için ayarlanmış; doğrusal
    /// altı ölçekleme küçük göstergeleri okunur tutuyor.
    private static func radiusScale(_ size: CGFloat, pow p: Double) -> Double {
        Foundation.pow(Double(size) / 300, p)
    }

    /// Eğik yörüngelerdeki parçacıklar — kitaplığın "working" kipi.
    /// Çekirdek yok: yalnızca hayalet yörüngeler ve üzerlerinde koşan
    /// parçacıklar.
    static func orbitsFrame(size: CGFloat, t: Double, preset: OrbPreset) -> [OrbDot] {
        let cx = Double(size) / 2
        let cy = Double(size) / 2
        let bigR = (Double(size) / 2) * 0.82
        let rs = radiusScale(size, pow: 0.6)

        // Ortak dönüş + eğim + ortografik izdüşüm.
        let yaw = t * 0.12
        let tilt = 0.3
        let st = sin(tilt), ct = cos(tilt)
        let sy = sin(yaw), cyw = cos(yaw)
        func project(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            return (cx + x1, cy - y1, z2)
        }

        var dots: [OrbDot] = []
        dots.reserveCapacity(preset.orbitN * (preset.ghostN + preset.particles))

        for orb in 0..<preset.orbitN {
            let h1 = hashD(Double(orb), 1.7)
            let h2 = hashD(Double(orb), 5.2)
            let h3 = hashD(Double(orb), 8.9)
            let ro = bigR * (0.45 + 0.52 * h1)
            let th = h1 * 2 * .pi
            let phi = acos(2 * h2 - 1)

            // Yörünge düzleminin tabanı (u, v ⟂ n).
            let nx = sin(phi) * cos(th)
            let ny = cos(phi)
            let nz = sin(phi) * sin(th)
            var ux = -ny
            var uy = nx
            let uz = 0.0
            let ul = max(1e-6, (ux * ux + uy * uy).squareRoot())
            ux /= ul
            uy /= ul
            let vx = ny * uz - nz * uy
            let vy = nz * ux - nx * uz
            let vz = nx * uy - ny * ux
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)

            // Hayalet yol: yörüngenin kendisi.
            for k in 0..<preset.ghostN {
                let a = (Double(k) / Double(preset.ghostN)) * 2 * .pi
                let (px, py, z) = project(
                    (ux * cos(a) + vx * sin(a)) * ro,
                    (uy * cos(a) + vy * sin(a)) * ro,
                    (uz * cos(a) + vz * sin(a)) * ro
                )
                let depth = (z / ro + 1) / 2
                let alpha = preset.ghostA * (0.4 + 0.6 * depth)
                guard alpha >= 0.02 else { continue }
                dots.append(
                    OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: z,
                        r: CGFloat(max(rMin, preset.ghostR * rs)),
                        white: 0.72,
                        alpha: alpha
                    )
                )
            }

            // İşi yapan parçacıklar.
            for m in 0..<preset.particles {
                let a = t * speed + (Double(m) / Double(preset.particles)) * 2 * .pi + h2 * 6
                let (px, py, z) = project(
                    (ux * cos(a) + vx * sin(a)) * ro,
                    (uy * cos(a) + vy * sin(a)) * ro,
                    (uz * cos(a) + vz * sin(a)) * ro
                )
                let depth = (z / ro + 1) / 2
                dots.append(
                    OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: z,
                        r: CGFloat(max(rMin, (preset.partR + preset.partRDepth * depth) * rs)),
                        white: 0.3 - 0.22 * depth,
                        alpha: 1
                    )
                )
            }
        }

        // Uzaktan yakına: yakın noktalar üstte kalsın.
        dots.sort { $0.z < $1.z }
        return dots
    }
}
