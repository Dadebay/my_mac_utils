import SwiftUI

/// Notun görünüm ayarlarının saklandığı anahtarlar.
enum NoteAppearance {
    /// Not, uygulamanın genel temasından bağımsız olarak açık/koyu
    /// olabiliyor — masaüstünde tek başına duran bir kâğıt gibi.
    static let themeKey = "poppedNote.theme"

    /// Not metninin boyut çarpanı. Mutlak punto yerine çarpan: başlık,
    /// madde ve gövde arasındaki oran korunuyor — hepsini tek tek
    /// saklasaydık biri büyütülüp öteki unutulabilirdi.
    static let fontScaleKey = "poppedNote.fontScale"
    static let defaultFontScale: Double = 1.0
    static let fontScaleRange: ClosedRange<Double> = 0.8...1.8
    static let fontScaleStep: Double = 0.1

    /// Kayıtlı değeri sınırların içine çeker.
    static func clampedFontScale(_ value: Double) -> Double {
        min(max(value, fontScaleRange.lowerBound), fontScaleRange.upperBound)
    }
}

/// Yapışkan notunun başlık şeridi rengi.
///
/// Tonlar bilerek doygunluğu düşürülmüş: şerit notu tanıtan bir işaret,
/// dikkat çeken bir uyarı değil. Önceki canlı renkler masaüstünde tek
/// başına duran küçük bir pencerede göze batıyor, altındaki içerikten
/// daha çok bakılan yer hâline geliyordu. Renkler birbirinden hâlâ
/// ayrışıyor — amaç ayırt edilebilirlik, vurgu değil.
enum NoteTint: Int, CaseIterable, Identifiable {
    case amber, coral, rose, mint, sky, violet

    var id: Int { rawValue }

    static let storageKey = "poppedNote.tint"
    static let opacityKey = "poppedNote.opacity"
    static let defaultOpacity: Double = 1.0
    /// Tamamen görünmez olup kullanıcının notu bulamaması engelleniyor.
    static let opacityRange: ClosedRange<Double> = 0.35...1.0

    /// Şerit düz renk yerine hafif bir degrade — yapışkan kâğıdın ışık alan
    /// üst kenarını taklit ediyor.
    var gradient: LinearGradient {
        LinearGradient(colors: [light, base], startPoint: .top, endPoint: .bottom)
    }

    var base: Color {
        switch self {
        case .amber: Color(red: 0.56, green: 0.45, blue: 0.26)
        case .coral: Color(red: 0.57, green: 0.37, blue: 0.32)
        case .rose: Color(red: 0.55, green: 0.35, blue: 0.44)
        case .mint: Color(red: 0.28, green: 0.49, blue: 0.43)
        case .sky: Color(red: 0.29, green: 0.42, blue: 0.57)
        case .violet: Color(red: 0.41, green: 0.37, blue: 0.58)
        }
    }

    private var light: Color {
        switch self {
        case .amber: Color(red: 0.64, green: 0.53, blue: 0.33)
        case .coral: Color(red: 0.65, green: 0.45, blue: 0.40)
        case .rose: Color(red: 0.63, green: 0.43, blue: 0.52)
        case .mint: Color(red: 0.35, green: 0.57, blue: 0.51)
        case .sky: Color(red: 0.36, green: 0.50, blue: 0.65)
        case .violet: Color(red: 0.49, green: 0.45, blue: 0.67)
        }
    }

    /// Şerit üzerindeki yazı ve düğme rengi. Tonlar koyulaştığı için
    /// sabit siyah bazılarında okunmaz hâle geliyordu; karar rengin
    /// parlaklığından geliyor, elle seçilmiyor.
    var foreground: Color {
        let components: (r: Double, g: Double, b: Double) = switch self {
        case .amber: (0.56, 0.45, 0.26)
        case .coral: (0.57, 0.37, 0.32)
        case .rose: (0.55, 0.35, 0.44)
        case .mint: (0.28, 0.49, 0.43)
        case .sky: (0.29, 0.42, 0.57)
        case .violet: (0.41, 0.37, 0.58)
        }
        let luminance = 0.2126 * components.r + 0.7152 * components.g + 0.0722 * components.b
        return luminance > 0.55 ? .black.opacity(0.7) : .white.opacity(0.92)
    }

    static func current(_ raw: Int) -> NoteTint {
        NoteTint(rawValue: raw) ?? .amber
    }
}
