import Foundation

/// Ağ geçmişi ajanının açık/kapalı durumu ve kayıt durumu.
///
/// Hem ana uygulama hem arka plan ajanı aynı paylaşılan `UserDefaults`
/// süitini (App Group) okuyor — ayrı bir IPC kanalına gerek kalmadan
/// ikisi de aynı anda aynı durumu görüyor. `isEnabled`, kullanıcının
/// Ayarlar'daki anahtarı; ajanın kendisi açılışında bunu okuyup kapalıysa
/// hemen kendini kapatıyor (bkz. `GlassDoNetworkAgent/main.swift`).
enum NetworkAgentSettings {
    static let enabledKey = "network.agent.enabled"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SystemSnapshotStore.appGroupIdentifier) ?? .standard
    }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }
}
