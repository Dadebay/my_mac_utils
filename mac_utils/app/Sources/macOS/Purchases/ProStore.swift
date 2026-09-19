import Foundation
import FirebaseAuth
import FirebaseCore
import GlassDoKit
import RevenueCat

/// Pro üyeliğin tek doğruluk kaynağı.
///
/// Yetki kararı **RevenueCat'ten** geliyor, uygulamanın kendi kaydından
/// değil: makbuz doğrulaması RevenueCat sunucusunda yapılıyor, bu yüzden
/// cihazdaki bir bayrağı kurcalayarak Pro açılamıyor. Firestore'a yalnızca
/// bir **kopya** yazılıyor (kendi istatistiğimiz için) — o kopya hiçbir
/// zaman "Pro mu?" sorusunun cevabı olarak okunmuyor.
@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    private(set) var isPro = false
    private(set) var packages: [Package] = []
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    /// Kullanıcıya gösterilebilecek son hata; başarılı her işlemde temizlenir.
    private(set) var errorMessage: String?
    /// Anahtar girilmemişse false kalır — paywall bunu görüp "yakında"
    /// yerine yapılandırma eksikliğini söyleyebilir.
    private(set) var isAvailable = false

    private var customerInfoTask: _Concurrency.Task<Void, Never>?

    private init() {}

    // MARK: - Kurulum

    /// Uygulama açılışında bir kez. Anahtar yoksa hiçbir şey yapmaz.
    func start() async {
        guard PurchaseConfig.isConfigured, !isAvailable else { return }

        let userID = await anonymousUserID()

        Purchases.logLevel = .warn
        let configuration = Configuration.Builder(withAPIKey: PurchaseConfig.publicAPIKey)
            .with(appUserID: userID)
            .build()
        Purchases.configure(with: configuration)

        isAvailable = true

        await refresh()
        observeCustomerInfo()
    }

    /// RevenueCat'in `appUserID`'si olarak Firebase anonim oturumunun
    /// `uid`'si kullanılıyor — bkz. `project.yml`'deki gerekçe.
    /// Oturum açılamazsa (ağ yok vb.) `nil` dönüp RevenueCat'in kendi
    /// anonim kimliğine bırakılıyor; satın alma yine çalışır, yalnızca
    /// ileride promo kod eşleşmesi kurulamaz.
    private func anonymousUserID() async -> String? {
        guard FirebaseApp.app() != nil else { return nil }
        if let current = Auth.auth().currentUser { return current.uid }
        do {
            return try await Auth.auth().signInAnonymously().user.uid
        } catch {
            print("[ProStore] anonim oturum açılamadı: \(error)")
            return nil
        }
    }

    /// Satın alma başka bir cihazda/başka bir akışta değişebilir (promo kod,
    /// iptal, yenileme). Akışı dinlemek, uygulamayı yeniden başlatmadan
    /// güncel kalmayı sağlıyor.
    private func observeCustomerInfo() {
        customerInfoTask?.cancel()
        customerInfoTask = _Concurrency.Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard !_Concurrency.Task.isCancelled else { return }
                self?.apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        isPro = info.entitlements[PurchaseConfig.entitlementID]?.isActive == true
    }

    // MARK: - Veri

    /// Hem güncel yetkiyi hem satılabilir paketleri tazeler.
    func refresh() async {
        guard isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
        } catch {
            errorMessage = error.localizedDescription
        }

        do {
            let offerings = try await Purchases.shared.offerings()
            packages = offerings.current?.availablePackages ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Eylemler

    func purchase(_ package: Package) async {
        guard isAvailable, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            // Kullanıcı App Store sayfasını kapattığında hata değil, iptal:
            // burada bir hata mesajı göstermek yanıltıcı olurdu.
            guard !result.userCancelled else { return }
            apply(result.customerInfo)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Aynı Apple kimliğiyle daha önce satın alınmışsa geri yükler.
    /// App Store incelemesi bu düğmenin varlığını şart koşuyor.
    func restore() async {
        guard isAvailable, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            errorMessage = isPro ? nil : L10n.purchaseNothingToRestore
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
