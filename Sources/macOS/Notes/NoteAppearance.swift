import SwiftUI

/// Notun görünüm ayarlarının saklandığı anahtarlar.
enum NoteAppearance {
    /// Not, uygulamanın genel temasından bağımsız olarak açık/koyu
    /// olabiliyor — masaüstünde tek başına duran bir kâğıt gibi.
    static let themeKey = "poppedNote.theme"
}

/// Yapışkan notun başlık şeridi rengi. Solgun pastel tonlar yerine, koyu
/// zeminde gerçekten öne çıkan canlı yapışkan kâğıt renkleri.
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
        case .amber: Color(red: 0.98, green: 0.75, blue: 0.18)
        case .coral: Color(red: 0.98, green: 0.48, blue: 0.34)
        case .rose: Color(red: 0.96, green: 0.42, blue: 0.62)
        case .mint: Color(red: 0.24, green: 0.82, blue: 0.60)
        case .sky: Color(red: 0.26, green: 0.68, blue: 0.98)
        case .violet: Color(red: 0.62, green: 0.46, blue: 0.98)
        }
    }

    private var light: Color {
        switch self {
        case .amber: Color(red: 1.00, green: 0.84, blue: 0.36)
        case .coral: Color(red: 1.00, green: 0.62, blue: 0.48)
        case .rose: Color(red: 1.00, green: 0.58, blue: 0.74)
        case .mint: Color(red: 0.42, green: 0.90, blue: 0.70)
        case .sky: Color(red: 0.44, green: 0.79, blue: 1.00)
        case .violet: Color(red: 0.74, green: 0.60, blue: 1.00)
        }
    }

    static func current(_ raw: Int) -> NoteTint {
        NoteTint(rawValue: raw) ?? .amber
    }
}
