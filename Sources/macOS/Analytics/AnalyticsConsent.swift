import Foundation

/// Kullanım verisi toplamak için kullanıcı iznini tutar. `DeviceAnalyticsService`
/// bu iznin "evet" olduğu her açılışta çalışır; sorulmadan ya da reddedilmişken
/// hiçbir zaman Firestore'a yazmaz.
///
/// İki ayrı bayrak var (`asked` + `granted`) çünkü "hiç sorulmadı" ile
/// "soruldu ve hayır dendi" farklı durumlar: ilki uygulama açılışında izin
/// ekranını göstermeli, ikincisi göstermemeli.
@MainActor
enum AnalyticsConsent {
    private static let askedKey = "analytics.consentAsked"
    private static let grantedKey = "analytics.consentGranted"

    static var hasBeenAsked: Bool {
        UserDefaults.standard.bool(forKey: askedKey)
    }

    static var isGranted: Bool {
        UserDefaults.standard.bool(forKey: grantedKey)
    }

    /// İzin ekranındaki seçim ya da Ayarlar'daki anahtar tarafından çağrılır.
    static func setGranted(_ granted: Bool) {
        UserDefaults.standard.set(true, forKey: askedKey)
        UserDefaults.standard.set(granted, forKey: grantedKey)
    }
}
