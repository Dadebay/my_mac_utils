import Foundation
import ServiceManagement

/// Arka plan ağ ajanının (`GlassDoNetworkAgent`) kayıt durumunu yönetir.
///
/// `SMAppService`, uygulama paketi içine gömülü bir `launchd` ajanını
/// kullanıcının oturumuna kaydetmenin modern yolu — elle
/// `~/Library/LaunchAgents/` içine plist yazmaktan farklı olarak macOS
/// tarafından takip ediliyor (Sistem Ayarları > Genel > Oturum Açma
/// Öğeleri'nde görünüyor, uygulama silinince otomatik temizleniyor).
@MainActor
@Observable
final class NetworkAgentController {
    static let shared = NetworkAgentController()

    private static let plistName = "com.dadebay.GlassDo.NetworkAgent.plist"

    private var service: SMAppService { .agent(plistName: Self.plistName) }

    /// Kullanıcının niyeti (Ayarlar'daki anahtar) — `NetworkAgentSettings`
    /// üzerinden ajanın kendisiyle paylaşılıyor.
    private(set) var isEnabled: Bool
    private(set) var status: SMAppService.Status
    /// Kayıt sırasında oluşan hata — kullanıcıya kısa bir açıklama olarak
    /// gösteriliyor. Genelde macOS'un onay isteyip henüz verilmediği
    /// (`.requiresApproval`) durumunda oluşuyor; o zaman hata değil,
    /// `status` zaten yeterli bilgi veriyor.
    private(set) var lastError: String?

    private init() {
        isEnabled = NetworkAgentSettings.isEnabled
        status = SMAppService.agent(plistName: Self.plistName).status
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        NetworkAgentSettings.isEnabled = enabled
        lastError = nil

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
            // Kayıt başarısız olduysa niyeti de geri al — anahtar açık
            // görünüp ajan aslında çalışmıyor olmasın.
            if enabled {
                isEnabled = false
                NetworkAgentSettings.isEnabled = false
            }
        }

        refreshStatus()
    }

    /// Sayfa her göründüğünde çağrılır: kullanıcı Sistem Ayarları'ndan
    /// onay verip geri dönmüş olabilir, `status` o değişikliğiburada
    /// yakalıyor.
    func refreshStatus() {
        status = service.status
    }

    /// macOS'un kendi "Oturum Açma Öğeleri" sayfasını açar — onay
    /// bekleyen bir ajan için tek düzeltme yolu bu, uygulama içinden
    /// otomatik onaylatılamıyor.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
