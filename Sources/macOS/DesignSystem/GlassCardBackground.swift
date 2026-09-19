import SwiftUI

/// Uygulamanın tek "cam kart" zemini — daha önce yalnızca Hakkında
/// sayfasında (`AboutGlassDoView`) vardı. `FormCard` düz, tek renkli bir
/// dolgu + tek renkli ince bir kenarlıkla çiziliyordu; bu, kullanıcının
/// "kötü tasarım" dediği görev ayrıntısı panelinde kartların koyu cam
/// zemine neredeyse hiç ayrışmadan karışmasına yol açıyordu. Buradaki
/// üstü biraz daha parlak kenarlık, ışığın camın üstünden geçtiği izlenimi
/// veriyor ve kartı zeminden gerçekten ayırıyor.
///
/// Increase Contrast'ta düz tek renk kenarlığa, Reduce Transparency'de daha
/// opak bir dolguya düşer — `AboutCardBackground` ile aynı erişilebilirlik
/// davranışı.
struct GlassCardBackground: ViewModifier {
    var cornerRadius: CGFloat = FormCardMetrics.cornerRadius

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var fillOpacity: Double { reduceTransparency ? 0.09 : 0.05 }
    private var borderOpacity: Double { contrast == .increased ? 0.22 : 0.09 }

    private var borderGradient: LinearGradient {
        contrast == .increased
            ? LinearGradient(colors: [Color.primary.opacity(borderOpacity)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [Color.primary.opacity(borderOpacity * 1.8), Color.primary.opacity(borderOpacity * 0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(borderGradient, lineWidth: contrast == .increased ? 1 : 0.75)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = FormCardMetrics.cornerRadius) -> some View {
        modifier(GlassCardBackground(cornerRadius: cornerRadius))
    }
}
