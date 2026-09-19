import SwiftUI

/// Ayar ve ayrıntı sayfalarındaki kartların ortak ölçüleri. Tek yerde
/// duruyor ki `glassCard(...)` ile elle çizilen kartlar aynı köşe
/// yarıçapını paylaşsın — birbirinden kayan yarıçaplar aynı sayfada iki
/// farklı kart dili gibi görünüyordu.
enum FormCardMetrics {
    static let cornerRadius: CGFloat = 12
    static let padding: CGFloat = 14
    static let spacing: CGFloat = 10
}

/// Cam zeminli, başlıklı bir form kartı. Başlık isteğe bağlı: yalnızca
/// içerik verildiğinde kart düz bir kutu gibi davranır.
struct FormCard<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FormCardMetrics.spacing) {
            if let title {
                Text(title)
                    .font(.app(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            content

            if let footnote {
                Text(footnote)
                    .font(.app(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FormCardMetrics.padding)
        .glassCard()
    }
}

/// Kart içindeki satırları ayıran ince çizgi. `Divider()` kartın dolgusunu
/// aşıp kenarlığa değdiği için kendi opaklığıyla ayrı duruyor.
struct FormCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

/// Kart satırlarının başındaki renkli simge rozeti. Simge boyu rozetin
/// boyuna oranlı — rozet büyüdüğünde simge orantısız kalmasın diye.
struct FormCardIcon: View {
    let systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .font(.app(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}
