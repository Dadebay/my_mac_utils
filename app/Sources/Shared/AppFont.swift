import AppKit
import SwiftUI

/// Uygulamanın kendi yazı tipi: Gilroy.
///
/// `Sources/Shared` içinde duruyor çünkü üç hedef de aynı yüzü kullanıyor:
/// ana pencere, kenar paneli ve widget uzantısı. Uzantı ayrı bir süreç,
/// yani yazı tipini kendi başına kaydetmek zorunda — ortak dosya bunu
/// tek bir yerden sağlıyor.
///
/// Kayıt başarısız olursa ya da istenen kesim bulunamazsa aynı boy ve
/// ağırlıkta sisteme düşülüyor: bir dosya eksik diye arayüzün yazısız
/// kalması, yanlış yazı tipiyle çizilmesinden beterdir.
enum AppFont {
    /// Pakete konan kesimler; adlar dosya adlarıyla birebir aynı.
    private static let faces = [
        "Gilroy-Regular", "Gilroy-Medium", "Gilroy-SemiBold", "Gilroy-Bold",
    ]

    /// Kayıt bir kez, ilk yazı tipi istendiğinde yapılıyor. `static let`
    /// Swift çalışma zamanında tembel ve iş parçacığı güvenli; ayrı bir
    /// bayrak ya da kilit gerekmiyor, uygulama ile widget uzantısının
    /// farklı süreçlerde aynı kodu çalıştırması da sorun olmuyor.
    private static let registration: Void = {
        for face in faces {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Gilroy'un paketteki dört kesimi var; aradaki ağırlıklar en yakınına
    /// yuvarlanıyor.
    private static func face(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: "Gilroy-Regular"
        case .medium: "Gilroy-Medium"
        case .semibold: "Gilroy-SemiBold"
        case .bold, .heavy, .black: "Gilroy-Bold"
        default: "Gilroy-Regular"
        }
    }

    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        _ = registration
        let name = face(for: weight)
        guard NSFont(name: name, size: size) != nil else {
            return .system(size: size, weight: weight)
        }
        return .custom(name, size: size)
    }

    /// `Font.app` ile aynı yazı tipi kararı, ama AppKit köprüleri
    /// (`NoteTextField` gibi doğrudan `NSFont` bekleyen görünümler) için.
    /// SwiftUI'ın `Font`'u oradan çizilmiyor — bu köprüler kullanılmazsa
    /// metin sessizce sisteme düşer.
    static func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        _ = registration
        let name = face(for: weight)
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private static func face(for weight: NSFont.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "Gilroy-Bold"
        case .semibold: "Gilroy-SemiBold"
        case .medium: "Gilroy-Medium"
        default: "Gilroy-Regular"
        }
    }
}

/// Punto ölçeği.
///
/// `.app(size:)` dört yüz çağrının her birinde çiğ bir sayı alıyordu ve
/// ortaya yirmi üç ayrı punto çıkmıştı (6.5, 7, 8.5, 9, 10, 11, 12, 13,
/// 14, 15, 16, 17, 19, 20, 22…). Yeni bir etiket yazarken "kaç punto?"
/// sorusunun cevabı yoktu; en yakın dosyadan kopyalanıyordu.
///
/// Basamaklar arayüzün gerçekten kullandığı yedi boydan geliyor. Dürüst
/// olmak gerekirse bunlar tasarlanmış bir ölçekten daha sıkışık —
/// 9'dan 15'e birer birer gidiyor, yani aralarında gerçek bir hiyerarşi
/// yok, zamanla oluşmuş bir süreklilik var. Buradaki iş o sürekliliği
/// adlandırıp yenilerinin eklenmesini durdurmak; basamak sayısını
/// azaltmak ayrı bir iş ve çalışan uygulamaya bakmayı gerektiriyor
/// (panel yüzeyleri dar, bir punto büyütmek satırı taşırabiliyor).
enum TextSize {
    /// Ölçer alt etiketi, rozet içi sayı.
    case micro
    /// İkincil, yardımcı metin.
    case caption
    /// Gövde metni — panelin varsayılanı, en kalabalık boy.
    case body
    /// Ana pencerenin gövde metni.
    case bodyLarge
    /// Kart ve bölüm başlığı.
    case headline
    /// Kenar çubuğu satırı, sayfa içi başlık.
    case title
    /// Sayfa başlığı.
    case titleLarge

    var points: CGFloat {
        switch self {
        case .micro: 9
        case .caption: 10
        case .body: 11
        case .bodyLarge: 12
        case .headline: 13
        case .title: 14
        case .titleLarge: 15
        }
    }
}

extension Font {
    /// Uygulamanın her yerinde `.system(size:weight:)` yerine bu kullanılıyor.
    /// Yazı tipi kararı arayüzün dört yüz ayrı noktasına dağılmasın diye
    /// tek bir geçit.
    static func app(_ size: TextSize, weight: Font.Weight = .regular) -> Font {
        AppFont.font(size: size.points, weight: weight)
    }

    /// Ölçek dışı boylar için. Ekran başına bir kez kullanılan iri
    /// okumalar (panelin CPU yüzdesi, Hakkında sayfasının başlığı,
    /// widget'ların büyük sayısı) burada kalıyor: her biri kendi dar
    /// kutusuna göre seçilmiş ve ortak bir basamağa oturtmak taşırıyor.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AppFont.font(size: size, weight: weight)
    }
}
