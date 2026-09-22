import SwiftUI
import AppKit

/// Bir dosyanın küçük resmini kare bir yuvada, **kırpmadan** gösterir.
///
/// Daha önce `.fill` kullanılıyordu: görüntü yuvayı dolduracak kadar
/// büyütülüp taşan yerleri kesiliyordu. Ekran görüntülerinde bu en can alıcı
/// kısmı — pencerenin üst ve alt kenarlarını — atıyor, geriye ortadan
/// rastgele bir kare kalıyordu. Dosyanın ne olduğu küçük resimden
/// anlaşılamıyordu.
///
/// Burada görüntü kendi en-boy oranıyla küçültülüp ortalanıyor; Pencere
/// Değiştirici'nin pencere önizlemelerinde yaptığının aynısı. Yuva kare
/// kalıyor ki ızgara hizası bozulmasın, artan yer de altındaki yüzeyle
/// dolduruluyor — böylece geniş bir görüntü boşlukta asılı kalmıyor.
struct ThumbnailTile: View {
    let image: NSImage?
    let size: CGFloat
    /// Yuvanın köşe yuvarlaklığı; görüntünün kendi köşesi bundan biraz
    /// daha küçük olur ki iç içe iki köşe eş merkezli görünsün.
    var cornerRadius: CGFloat = 8
    /// Küçük resim yoksa gösterilecek simge.
    var fallbackSymbol: String
    var fallbackSymbolSize: CGFloat = 20

    /// Görüntü ile yuva kenarı arasındaki pay. Sıfır olsaydı sığdırma
    /// yalnızca tek eksende kenara değer, diğerinde boşluk kalırdı; küçük
    /// bir pay bunu kasıtlı gösteriyor.
    private var inset: CGFloat { max(size * 0.045, 2) }

    private var imageCornerRadius: CGFloat { max(cornerRadius - inset, 2) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.07))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    // Küçültme çok agresif (bazen 5× indirgeme); yüksek
                    // interpolasyon olmadan ince metinler bulanıyor.
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
                    .overlay {
                        // Açık zeminli ekran görüntüleri açık yüzeye
                        // karışmasın diye saç teli kalınlığında kenar.
                        RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                    }
                    .padding(inset)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: fallbackSymbolSize, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
