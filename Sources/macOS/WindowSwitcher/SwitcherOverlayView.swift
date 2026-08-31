import SwiftUI
import GlassDoKit

/// AltTab'ın kart şeridine benzer bindirim: her açık pencere, canlı bir
/// küçük resim ve uygulama ikonu/adıyla gösterilir; seçili kart vurgu
/// rengiyle çerçevelenir.
struct SwitcherOverlayView: View {
    let windows: [SwitcherWindowInfo]
    let selectedIndex: Int
    /// Bir karta mouse ile tıklanınca o pencereyi doğrudan öne getirir.
    let onSelect: (SwitcherWindowInfo) -> Void
    /// Kartların dışına (zemine) tıklanınca bindirimi kapatır.
    let onDismiss: () -> Void
    /// Kartın üzerindeki kırmızı düğme — pencerenin uygulamasından tamamen çıkar.
    let onClose: (SwitcherWindowInfo) -> Void
    /// Sarı düğme — pencereyi simge durumuna küçültür.
    let onMinimize: (SwitcherWindowInfo) -> Void
    /// Yeşil düğme — pencereyi büyütür/eski haline getirir.
    let onMaximize: (SwitcherWindowInfo) -> Void
    /// Bir satırın taşmadan kaplayabileceği en fazla genişlik; aşılınca
    /// kartlar alt satıra sarılır.
    let maxRowWidth: CGFloat

    /// Küçük resmin sabit yüksekliği — genişlik pencerenin en-boy oranından
    /// türetiliyor, böylece pencere kırpılmadan tamamı görünüyor.
    /// TÜM kartlarda ortak, sabit görüntü yüksekliği — dikey bir pencere de
    /// (Happ) yatay bir pencere de (VS Code, Claude) aynı yükseklikte durur,
    /// yalnızca genişlikleri kendi en-boy oranlarına göre değişir.
    static let thumbnailHeight: CGFloat = 190
    /// Aşırı dar/geniş pencerelerde kartın kullanışsız hâle gelmemesi için
    /// sınırlar (bunların dışında kalan oranlarda küçük bir boşluk oluşur).
    /// Üst sınır, ekranı kaplayan 16:9 bir pencerenin (≈345pt) kırpılmadan
    /// tam genişliğine ulaşabilmesi için bunun üzerinde tutuluyor.
    static let minCardWidth: CGFloat = 104
    static let maxCardWidth: CGFloat = 440
    static let cardSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 12

    static func cardWidth(for window: SwitcherWindowInfo) -> CGFloat {
        min(max(thumbnailHeight * window.aspectRatio, minCardWidth), maxCardWidth)
    }

    /// Kartları, hiçbiri ekrandan taşmayacak şekilde satırlara böler.
    static func rows(for windows: [SwitcherWindowInfo], maxWidth: CGFloat) -> [[SwitcherWindowInfo]] {
        var rows: [[SwitcherWindowInfo]] = []
        var current: [SwitcherWindowInfo] = []
        var currentWidth: CGFloat = 0

        for window in windows {
            let width = cardWidth(for: window)
            let projected = current.isEmpty ? width : currentWidth + cardSpacing + width
            if projected > maxWidth, !current.isEmpty {
                rows.append(current)
                current = [window]
                currentWidth = width
            } else {
                current.append(window)
                currentWidth = projected
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private var layoutRows: [[SwitcherWindowInfo]] {
        Self.rows(for: windows, maxWidth: maxRowWidth)
    }

    var body: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(Array(layoutRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.cardSpacing) {
                    ForEach(row) { window in
                        card(window, isSelected: windows.firstIndex(where: { $0.id == window.id }) == selectedIndex)
                    }
                }
            }
        }
        .padding(20)
        .fixedSize()
        // "Dışarı tıklayınca kapat" yalnızca zemine bağlı: daha önce tüm
        // yığının üstündeydi ve kartların kendi dokunma hedefiyle
        // yarışıyordu — tıklama bazen kartı seçmek yerine bindirimi
        // kapatmakla sonuçlanıyordu.
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.001))
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
        .preferredColorScheme(.dark)
    }

    private func card(_ window: SwitcherWindowInfo, isSelected: Bool) -> some View {
        CardView(
            window: window, isSelected: isSelected,
            onSelect: { onSelect(window) },
            onClose: { onClose(window) },
            onMinimize: { onMinimize(window) },
            onMaximize: { onMaximize(window) }
        )
        .frame(width: Self.cardWidth(for: window))
    }

    private struct CardView: View {
        let window: SwitcherWindowInfo
        let isSelected: Bool
        let onSelect: () -> Void
        let onClose: () -> Void
        let onMinimize: () -> Void
        let onMaximize: () -> Void

        @State private var isHovering = false
        @State private var thumbnailVisible = false

        private var isHighlighted: Bool { isSelected || isHovering }

        /// Küçük resmi olmayan giriş: pencere ekranda değil (hepsi simge
        /// durumunda) — kart, macOS'un kendi uygulama değiştiricisindeki
        /// gibi büyük bir uygulama logosu ve altında küçük bir "simge
        /// durumunda" göstergesiyle çizilir.
        private var isIconOnly: Bool { window.thumbnail == nil }

        /// Çerçeve yalnızca seçimi/hover'ı anlatır ve kartın TAMAMINI sarar —
        /// pencere görüntüsünün kendisi hiçbir kalıba sokulmaz.
        private var cardBorderColor: Color {
            if isSelected { return Color(nsColor: .systemBlue) }
            if isHovering { return Color.white.opacity(0.35) }
            return .clear
        }

        var body: some View {
            VStack(spacing: 7) {
                // Uygulama ikonu ve adı — referanstaki gibi görüntünün üstünde.
                HStack(spacing: 6) {
                    if let icon = window.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 17, height: 17)
                    }
                    Text(window.appName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // Pencere Dock'ta simge durumunda — kart yine de son
                    // görüntüsünü gösterdiği için ayırt edici bir işaret gerek.
                    if window.isMinimized {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 1.0, green: 0.74, blue: 0.18))
                            .help(L10n.s("Simge durumunda", "Minimized", "Свёрнуто"))
                    }

                    if let profileLabel = window.profileLabel {
                        Text(profileLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color(nsColor: .systemBlue).opacity(0.35)))
                    }

                    Spacer(minLength: 0)
                }

                ZStack(alignment: .topLeading) {
                    if let thumbnail = window.thumbnail {
                        // Pencere olduğu gibi, yalnızca küçültülerek çizilir:
                        // ne kırpılır ne de yuvarlak bir kalıba sokulur.
                        Image(nsImage: thumbnail)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(thumbnailVisible ? 1 : 0)
                            .onAppear {
                                if WindowSwitcherSettings.fadeInPreviewEnabled {
                                    withAnimation(.easeOut(duration: 0.18)) { thumbnailVisible = true }
                                } else {
                                    thumbnailVisible = true
                                }
                            }
                    } else if let icon = window.icon {
                        VStack(spacing: 7) {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 76, height: 76)

                            // Simge durumundaki pencereyi anlatan küçük çizgi.
                            Capsule()
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 16, height: 3)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if isHovering {
                        windowControls
                            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .topLeading)))
                    }
                }
                // Genişlik dışarıdan (kartın en-boy oranına göre) veriliyor.
                .frame(height: SwitcherOverlayView.thumbnailHeight)
                .animation(.easeOut(duration: 0.12), value: isHovering)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.10 : (isHovering ? 0.07 : 0.0001)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: isSelected ? 3 : 1)
            }
            .scaleEffect(isHighlighted ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHighlighted)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture(perform: onSelect)
        }

        /// Gerçek pencere trafik ışıklarını taklit eden kapat/küçült/büyüt
        /// düğmeleri — yalnızca kart hover'dayken görünür.
        private var windowControls: some View {
            HStack(spacing: 6) {
                trafficLight(color: Color(red: 1.0, green: 0.37, blue: 0.34), systemName: "xmark", action: onClose)
                trafficLight(color: Color(red: 1.0, green: 0.74, blue: 0.18), systemName: "minus", action: onMinimize)
                trafficLight(color: Color(red: 0.16, green: 0.78, blue: 0.35), systemName: "arrow.up.left.and.arrow.down.right", action: onMaximize)
            }
        }

        private func trafficLight(color: Color, systemName: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                ZStack {
                    Circle().fill(color)
                    Image(systemName: systemName)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                }
                .frame(width: 13, height: 13)
            }
            .buttonStyle(.plain)
        }
    }
}
