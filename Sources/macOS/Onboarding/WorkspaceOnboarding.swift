import Foundation

/// İlk açılışta çalışma alanı seçim sayfasının gösterilip gösterilmediğini
/// tutar. `AnalyticsConsent` ile aynı desen: bir kez sorulur, kullanıcı ne
/// seçerse seçsin (şablon uygulasın ya da "Boş Başla" desin) bir daha
/// gösterilmez — özelliğin kendisine Ayarlar > Çalışma Alanları'ndan her
/// zaman erişilebilir.
@MainActor
enum WorkspaceOnboarding {
    private static let shownKey = "workspace.onboardingShown"

    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: shownKey)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: shownKey)
    }
}
