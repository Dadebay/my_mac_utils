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

extension Font {
    /// Uygulamanın her yerinde `.system(size:weight:)` yerine bu kullanılıyor.
    /// Yazı tipi kararı arayüzün dört yüz ayrı noktasına dağılmasın diye
    /// tek bir geçit.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AppFont.font(size: size, weight: weight)
    }
}
