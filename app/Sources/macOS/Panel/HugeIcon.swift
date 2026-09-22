import SwiftUI

/// Hugeicons çizgi ikonları.
///
/// SF Symbols yerine raf sayfasında bunlar kullanılıyor: hepsi 24×24
/// ızgarada, 1.5 pt tek kalınlıkta çizilmiş — SF Symbols'ün optik boy ve
/// ağırlık değişkenliği yerine tek tip bir çizgi dili.
///
/// Kaynak: https://hugeicons.com — `@hugeicons/core-free-icons` (MIT,
/// © 2025 Hugeicons). Swift paketi yok; ihtiyaç duyulan ikonların SVG'leri
/// paketten üretilip `Assets.xcassets`'e vektör olarak konuldu
/// ("preserves-vector-representation" + şablon çizim), böylece her boyda
/// keskin kalıyor ve rengi `foregroundStyle`'dan alıyor.
struct HugeIcon: View {
    let name: HugeIconName
    /// SF Symbols punto karşılığı — yanına yazılan metnin punto'suyla aynı
    /// sayıyı vermek yeterli, optik düzeltme aşağıda yapılıyor.
    var size: CGFloat = 13

    /// Hugeicons 24×24'lük bir kutuyu baştan sona dolduruyor; SF Symbols ise
    /// aynı puntoda kutusunun yalnızca ~%70'ini kaplıyor (harf yüksekliği
    /// kadar). Bu yüzden ikonlar aynı sayı verildiğinde metnin ve komşu SF
    /// sembollerinin yanında gözle görülür biçimde iri duruyordu. Çarpan
    /// tek yerde: her çağrı noktasında ayrı ayrı küçültülseydi, biri
    /// unutulduğunda o ikon yine iri kalırdı.
    private static let opticalScale: CGFloat = 0.82

    private var renderedSize: CGFloat { (size * Self.opticalScale).rounded() }

    var body: some View {
        Image(name.rawValue)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: renderedSize, height: renderedSize)
            // Dokunma/tıklama hedefi optik küçültmeden etkilenmiyor: çizim
            // küçüldü, düğmenin kendisi küçülmemeli.
            .frame(width: size, height: size)
    }
}

/// Varlık kataloğundaki ikon adları. Serbest metin yerine sabit bir küme:
/// yazım hatası derleme zamanında yakalanıyor, çalışırken boş kare
/// çıkmıyor.
enum HugeIconName: String {
    case eye = "hg-eye"
    case copy = "hg-copy"
    case link = "hg-link"
    case open = "hg-open"
    case folder = "hg-folder"
    case rename = "hg-rename"
    case close = "hg-close"
    case trash = "hg-trash"
    case plus = "hg-plus"
    case more = "hg-more"
    case grid = "hg-grid"
    case list = "hg-list"
    case sort = "hg-sort"
    case shelf = "hg-shelf"
    case drop = "hg-drop"
    case alert = "hg-alert"
    case back = "hg-back"
    case image = "hg-image"
    case pdf = "hg-pdf"
    case archive = "hg-archive"
    case file = "hg-file"
    case audio = "hg-audio"
    case video = "hg-video"
    // Pano içerik türleri ve kopyalama onayı. Hugeicons'ın ücretsiz
    // setinde karşılıkları yoktu; aynı 24×24 ızgarada, 1.5 pt tek
    // kalınlıkta çizilip pakete eklendi.
    case terminal = "hg-terminal"
    case code = "hg-code"
    case text = "hg-text"
    case check = "hg-check"
    case refresh = "hg-refresh"
}

extension StorageItemKind {
    /// Dosya türünün raf sayfasındaki karşılığı. `symbolName` (SF Symbols)
    /// duruyor: onu panelin başka yerleri de kullanıyor.
    var hugeIcon: HugeIconName {
        switch self {
        case .image: .image
        case .audio: .audio
        case .video: .video
        case .pdf: .pdf
        case .archive: .archive
        case .file: .file
        }
    }
}

extension Label where Title == Text, Icon == HugeIcon {
    /// Menü satırları için: `Button(_:systemImage:)`'ın Hugeicons karşılığı.
    /// Optik düzeltme `HugeIcon`'un kendisinde olduğu için buradaki punto
    /// doğrudan metnin puntosuyla eşleşebiliyor.
    init(_ title: String, huge icon: HugeIconName, size: CGFloat = 13) {
        self.init {
            Text(title)
        } icon: {
            HugeIcon(name: icon, size: size)
        }
    }
}
