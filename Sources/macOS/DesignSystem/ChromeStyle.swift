import SwiftUI

/// Uygulamanın kabuk dili: renkler, metin kademeleri ve ortam ışığı.
///
/// Kenar çubuğu ile pano aynı ışığı paylaşıyor. İki yüzey kendi paletini
/// tutsaydı biri ayarlandığında öteki geride kalır, pencerenin iki yarısı
/// farklı iki uygulamadan gelmiş gibi görünürdü.
enum ChromePalette {
    /// Zemin: yukarıdan aşağı hafifçe koyulaşan lacivert.
    static let base0 = Color(red: 0.031, green: 0.043, blue: 0.086)
    static let base1 = Color(red: 0.043, green: 0.063, blue: 0.125)
    static let base2 = Color(red: 0.051, green: 0.071, blue: 0.141)

    /// Ortam ışığının üç kaynağı. Tek bir ışık alanının farklı yerlerdeki
    /// tonları — birbirinden bağımsız süsler değil.
    static let indigo = Color(red: 0.42, green: 0.36, blue: 0.95)
    static let blue = Color(red: 0.24, green: 0.52, blue: 0.98)
    static let violet = Color(red: 0.55, green: 0.34, blue: 0.92)

    /// Seçili/etkin yüzeylerin camı.
    static let selectionTop = Color(red: 0.13, green: 0.43, blue: 0.86)
    static let selectionMid = Color(red: 0.15, green: 0.28, blue: 0.67)
    static let selectionEnd = Color(red: 0.32, green: 0.20, blue: 0.71)
    static let selectionEdge = Color(red: 0.31, green: 0.59, blue: 1.0)

    static let progressStart = Color(red: 0.24, green: 0.80, blue: 0.56)
    static let progressEnd = Color(red: 0.36, green: 0.72, blue: 0.98)
    static let statusDot = Color(red: 0.30, green: 0.85, blue: 0.52)

    static let hairline = Color.white.opacity(0.10)
}

/// Metin kademeleri. Açık temada beyaz tonları okunmaz olurdu; oradaki
/// karşılıkları sistemin kendi anlamsal renkleri.
struct ChromeTextTiers {
    let primary: Color
    let secondary: Color
    let section: Color
    let label: Color
    let selectedLabel: Color

    static func resolve(_ scheme: ColorScheme) -> ChromeTextTiers {
        guard scheme == .dark else {
            return ChromeTextTiers(
                primary: .primary,
                secondary: .secondary,
                section: Color(nsColor: .tertiaryLabelColor),
                label: .primary,
                selectedLabel: .primary
            )
        }
        return ChromeTextTiers(
            primary: .white.opacity(0.88),
            secondary: .white.opacity(0.58),
            section: .white.opacity(0.32),
            label: .white.opacity(0.78),
            selectedLabel: .white.opacity(0.96)
        )
    }
}

/// Bir yüzeyin arkasındaki tek sürekli ışık alanı.
///
/// Parıltılar sağ üstten merkeze, oradan alta doğru akıyor ve `plusLighter`
/// ile birikiyor: üst üste binen yerler ayrı ayrı daireler gibi değil, tek
/// bir aydınlanma gibi okunuyor.
///
/// Yalnızca koyu temada çiziliyor. Açık temada sistemin kendi malzemesi
/// kalıyor — lacivert bir yüzey açık pencerede kara bir delik olurdu.
struct ChromeAmbience: View {
    enum Placement {
        /// Kenar çubuğu: dar, ışık belirgin, sol kenar karanlık.
        case sidebar
        /// İçerik alanı: geniş, ışık çok daha sessiz — kartların kendi
        /// yüzeyleri okunabilmeli, zemin onları bastırmamalı.
        case content
        /// Masaüstüne çıkarılmış widget: küçük yüzey, tek yumuşak parıltı.
        case widget
    }

    var placement: Placement = .sidebar

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var intensity: Double {
        switch placement {
        case .sidebar: 1.0
        case .content: 0.55
        case .widget: 0.8
        }
    }

    var body: some View {
        if colorScheme == .dark {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    LinearGradient(
                        stops: [
                            .init(color: ChromePalette.base2, location: 0),
                            .init(color: ChromePalette.base1, location: 0.55),
                            .init(color: ChromePalette.base0, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    // Reduce Transparency açıkken arkadaki masaüstü hiç
                    // sızmıyor; kapalıyken yüzey camlı kalıyor.
                    .opacity(reduceTransparency ? 1 : 0.88)

                    glow(ChromePalette.indigo, 0.10, UnitPoint(x: 1.02, y: 0.04), size, 1.15)
                    glow(ChromePalette.blue, 0.07, UnitPoint(x: 1.02, y: 0.42), size, 1.05)
                    glow(ChromePalette.violet, 0.075, UnitPoint(x: 0.45, y: 0.98), size, 1.1)

                    if placement == .sidebar {
                        // Sol kenar ışığın dışında: metin her zaman en
                        // sakin zeminin üstünde başlıyor.
                        LinearGradient(
                            colors: [Color.black.opacity(0.30), .clear],
                            startPoint: .leading,
                            endPoint: UnitPoint(x: 0.7, y: 0.5)
                        )
                    }

                    // Camın üst kenarındaki ince iç parlama.
                    LinearGradient(
                        colors: [Color.white.opacity(0.035), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.18)
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    private func glow(
        _ color: Color,
        _ opacity: Double,
        _ center: UnitPoint,
        _ size: CGSize,
        _ scale: CGFloat
    ) -> some View {
        RadialGradient(
            stops: [
                .init(color: color.opacity(opacity * intensity), location: 0),
                .init(color: color.opacity(opacity * intensity * 0.42), location: 0.38),
                .init(color: .clear, location: 1),
            ],
            center: center,
            startRadius: 0,
            endRadius: max(size.width, size.height) * scale
        )
        .blendMode(.plusLighter)
    }
}
