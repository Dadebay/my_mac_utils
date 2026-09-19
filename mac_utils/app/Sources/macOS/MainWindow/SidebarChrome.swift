import SwiftUI

/// Kenar çubuğuna özgü görsel parçalar: ikon karosu ve satır yüzeyi.
/// Renkler, metin kademeleri ve ortam ışığı panoyla ortak — bkz.
/// `ChromeStyle.swift`.
///
/// Gezinme mantığı `SidebarView`'da kalıyor; burada yalnızca nasıl
/// göründüğü var.

// MARK: - İkon karosu

/// Satır başlarındaki küçük uygulama ikonu. Işık sol üstten geliyor:
/// degrade, sedefi ve kenarlığı aynı yöne bakıyor, böylece karo boyalı bir
/// kare değil hacimli bir nesne gibi duruyor.
struct SidebarIconTile: View {
    let symbolName: String
    let colors: [Color]
    var size: CGFloat = 26
    var cornerRadius: CGFloat = 7.5
    var glyphSize: CGFloat = 13

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                // Sedef: üstte ışık, altta hafif gölge.
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.24), location: 0),
                            .init(color: .clear, location: 0.5),
                            .init(color: .black.opacity(0.12), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                    // Optik ortalama: SF sembollerinin çoğu kutusunun
                    // üstüne yaslanıyor.
                    .padding(.bottom, 1.5)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.26), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
            }
            .shadow(color: .black.opacity(0.26), radius: 2, y: 1)
    }
}

// MARK: - Satır yüzeyi

/// Satırların ortak zemini: seçili olan aydınlatılmış bir cam parçası,
/// üzerine gelinen yalnızca bir ton açılıyor, geri kalanı sessiz.
struct SidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        RowSurface(configuration: configuration, isSelected: isSelected, cornerRadius: cornerRadius)
    }

    private struct RowSurface: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        let cornerRadius: CGFloat

        @State private var isHovering = false
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        }

        private var isDark: Bool { colorScheme == .dark }

        var body: some View {
            configuration.label
                .background {
                    if isSelected {
                        selectionSurface
                    } else if isHovering {
                        shape.fill(Color.white.opacity(isDark ? 0.05 : 0.05))
                    }
                }
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: isSelected)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: configuration.isPressed)
                .onHover { isHovering = $0 }
        }

        /// Işığın içinden geçtiği cam: çapraz mavi-indigo degrade, ince
        /// mavi kenarlık, üstte iç parlama ve dışa çok yumuşak bir hale.
        @ViewBuilder
        private var selectionSurface: some View {
            if isDark {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                ChromePalette.selectionTop.opacity(0.32),
                                ChromePalette.selectionMid.opacity(0.24),
                                ChromePalette.selectionEnd.opacity(0.20),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        shape.strokeBorder(
                            ChromePalette.selectionEdge.opacity(0.26),
                            lineWidth: 0.8
                        )
                    }
                    .overlay {
                        // İç parlama yalnızca üst kenarda: ışık yukarıdan
                        // geliyor, çerçevenin tamamı parlarsa cam değil
                        // neon olurdu.
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.14), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                    }
                    .shadow(color: ChromePalette.selectionTop.opacity(0.18), radius: 10, y: 3)
            } else {
                shape
                    .fill(Color.accentColor.opacity(0.16))
                    .overlay { shape.strokeBorder(Color.accentColor.opacity(0.26), lineWidth: 0.8) }
            }
        }
    }
}
