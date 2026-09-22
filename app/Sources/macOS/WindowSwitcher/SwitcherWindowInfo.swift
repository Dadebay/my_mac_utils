import AppKit

/// AltTab bindirmesinde bir kart olarak gösterilen tek bir giriş — ya
/// gerçek bir pencere, ya da (o an hiç penceresi olmayan ama çalışan bir
/// uygulama için) yalnızca uygulama logosunu gösteren bir yer tutucu.
struct SwitcherWindowInfo: Identifiable {
    let id = UUID()
    /// `nil` ise bu, penceresiz bir uygulama girişidir — kart yalnızca
    /// ikonu gösterir, etkinleştirme de pencere yükseltmeden geçilir.
    let windowID: CGWindowID?
    let pid: pid_t
    let appName: String
    let windowTitle: String
    /// Ekran koordinatlarında pencere çerçevesi — Erişilebilirlik API'sinde
    /// aynı pencereyi başlığa göre değil konuma göre bulmak için kullanılır.
    /// Chrome gibi başlığı sürekli değişen (sayfa başlığı) uygulamalarda
    /// başlık eşleşmesi güvenilmezdi; bu da tıklayınca yanlış pencerenin
    /// öne gelmesine yol açabiliyordu.
    let frame: CGRect?
    let icon: NSImage?
    var thumbnail: NSImage?
    /// Pencere şu an Dock'ta simge durumunda. Küçük resmi, küçültülmeden
    /// önce yakalanıp önbelleğe alınmış görüntüden geliyor.
    var isMinimized: Bool = false

    /// Kartın genişliğini belirleyen en-boy oranı. Pencere kırpılmadan,
    /// tamamı küçültülerek gösterildiği için kart bu orana göre şekilleniyor:
    /// dikey bir pencere dar, geniş bir editör penceresi geniş kart alıyor.
    var aspectRatio: CGFloat {
        if let thumbnail, thumbnail.size.height > 0 {
            return thumbnail.size.width / thumbnail.size.height
        }
        if let frame, frame.height > 0 {
            return frame.width / frame.height
        }
        // Yalnızca logo gösteren kart — kare bir alan yeterli.
        return 1
    }

    /// Chromium tabanlı tarayıcılar (Chrome, Edge, Brave, Arc...) birden
    /// fazla profil açıkken pencere başlığının sonuna " - Profil Adı" ekler
    /// (ör. "Gelen Kutusu - Google Chrome - İş"). Bu son eki ayıklayıp,
    /// aynı uygulamanın hangi profile ait penceresi olduğunu bir rozetle
    /// göstermek için kullanıyoruz.
    var profileLabel: String? {
        let marker = " - \(appName) - "
        guard let range = windowTitle.range(of: marker) else { return nil }
        let suffix = windowTitle[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return suffix.isEmpty ? nil : suffix
    }
}
