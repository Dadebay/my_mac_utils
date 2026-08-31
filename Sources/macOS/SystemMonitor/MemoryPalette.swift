import SwiftUI

/// Bellek dağılım renkleri. Ana penceredeki RAM ekranı ve kenar panelindeki
/// kompakt sürüm aynı paletten okur — iki yerde ayrı ayrı tanımlanırsa
/// zamanla birbirinden kayarlar.
///
/// Mavi / turuncu / turkuaz: renk körlüğünde de parlaklık farkıyla ayrışıyor.
/// Her segmentin ayrıca metin etiketi var, yani renk tek başına bilgi
/// taşımıyor.
enum MemoryPalette {
    static let apps = Color(red: 0.24, green: 0.58, blue: 1.00)
    static let system = Color(red: 0.98, green: 0.62, blue: 0.20)
    static let cached = Color(red: 0.20, green: 0.72, blue: 0.72)
    static let free = Color.white.opacity(0.13)
}
