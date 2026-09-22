import Foundation

/// RevenueCat yapılandırması.
///
/// Buradaki anahtar **public SDK key** — RevenueCat'in tasarımı gereği
/// uygulama paketiyle dağıtılması normaldir, Firebase'in `GoogleService-Info`
/// dosyası gibi. Gizli olan `sk_` ile başlayan secret anahtardır; o yalnızca
/// `functions/` içindeki sunucu tarafında durur ve asla buraya konmaz —
/// paketten çıkarılabildiği için herkes kendine Pro verebilirdi.
enum PurchaseConfig {

    /// RevenueCat panosunda: Project settings → API keys → **Public app key**
    /// (`appl_...` ile başlar). Boş bırakılırsa satın alma katmanı hiç
    /// başlatılmaz; uygulama çalışmaya devam eder, yalnızca Pro kapalı kalır.
    static let publicAPIKey = ""

    /// `functions/src/**` içindeki `ENTITLEMENT_ID` ile birebir aynı olmak
    /// zorunda: promo kodla verilen hak ile satın almayla açılan hak aynı
    /// yetkiyi göstermezse, kod kullanan kullanıcıda Pro açılmaz.
    static let entitlementID = "pro"

    /// Anahtar girilmediyse tüm satın alma akışı sessizce devre dışı.
    static var isConfigured: Bool {
        !publicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
