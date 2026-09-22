import GlassDoKit
import SwiftUI

/// Pencerenin üst şeridi: solda açık olan sayfanın kimliği, sağda o
/// sayfanın kendi eylemleri.
///
/// Sistemin pencere başlığı gizleniyor. "GlassDo" yazısı her sayfada aynı
/// kalıyordu, yani üst şerit sürekli yer kaplayıp hiçbir soruyu
/// yanıtlamıyordu; oysa üst şeridin yanıtlaması gereken soru "neredeyim".
/// Kimlik kenar çubuğundaki satırla aynı simgeyi ve rengi taşıyor: iki
/// yerde aynı görsel, geçişte gözün takip edeceği tek bir çıpa.
struct PageToolbarBadge: View {
    let entry: SidebarEntry
    /// Sayfanın kendi ikinci satırı ("15 çekirdek", "Macintosh HD"). Yoksa
    /// başlık tek başına dikeyde ortalanıyor.
    var subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: entry.colors, startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: entry.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                }
                // Karo kendi renginin tonunda ince bir gölge bırakıyor:
                // düz zemine yapıştırılmış bir etiket değil, sayfanın
                // simgesi gibi duruyor.
                .shadow(color: (entry.colors.last ?? .black).opacity(0.35), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(.app(size: 15, weight: .semibold))
                    .kerning(-0.2)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.app(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .fixedSize()
        }
        // Araç çubuğu içeriğini kenardan yalnızca 1 pt ayırıyor; sayfa
        // içeriği ise `Layout.toolbarSideInset` kadar içeride. Aradaki fark
        // buradan kapatılıyor, rozet ile altındaki ilk sütun aynı dikey
        // çizgide başlıyor.
        .padding(.leading, Layout.toolbarSideInset - 1)
        .animation(.easeOut(duration: 0.18), value: entry.title)
        .animation(.easeOut(duration: 0.18), value: subtitle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(entry.title), \($0)" } ?? entry.title)
    }
}

// MARK: - Sayfa alt başlığı

/// Sayfanın üst şeritte görünecek ikinci satırı. Değer sayfanın kendisinde
/// (ölçümün yanında) biliniyor, gösterileceği yer ise pencerenin üstü —
/// ikisi arasındaki tek yönlü yol bu.
private struct PageSubtitleKey: PreferenceKey {
    static let defaultValue: String? = nil

    static func reduce(value: inout String?, nextValue: () -> String?) {
        // Son söyleyen kazanır: iç içe sayfalar olduğunda en derindeki,
        // yani kullanıcının gerçekten baktığı sayfa yazıyor.
        if let next = nextValue() { value = next }
    }
}

extension View {
    /// Üst şeritteki başlığın altına yazılacak satır.
    func pageSubtitle(_ subtitle: String?) -> some View {
        preference(key: PageSubtitleKey.self, value: subtitle)
    }

    /// Üst şerit, alt başlığı buradan okuyor.
    func onPageSubtitleChange(_ action: @escaping (String?) -> Void) -> some View {
        onPreferenceChange(PageSubtitleKey.self) { value in
            action(value)
        }
    }
}
