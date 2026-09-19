import SwiftUI

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Bu rengi hedefe doğru karıştırılmış hâli — `TintedIconBadge` gibi
    /// tek bir vurgu renginden, SwiftUI'ın otomatik (ve genelde çok soluk
    /// kalan) `.gradient`'i yerine, iki ucu kasıtlı olarak ayrılmış gerçek
    /// bir açık/koyu çift üretmek için.
    func mixed(towards target: Color, amount: Double) -> Color {
        let a = resolve(in: EnvironmentValues())
        let b = target.resolve(in: EnvironmentValues())
        let t = min(max(amount, 0), 1)
        return Color(
            red: Double(a.red) + (Double(b.red) - Double(a.red)) * t,
            green: Double(a.green) + (Double(b.green) - Double(a.green)) * t,
            blue: Double(a.blue) + (Double(b.blue) - Double(a.blue)) * t
        )
    }
}
