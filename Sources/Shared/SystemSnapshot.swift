import Foundation

/// Uygulamanın widget uzantısına bıraktığı son ölçüm.
///
/// Widget uzantısı kum havuzunda çalışıyor ve sıcaklık sensörlerine
/// (IOHID) oradan erişilemiyor; ayrıca "bugün / son 30 gün" ağ toplamları
/// yalnızca uygulama ömrü boyunca biriktirildiği için widget kendi başına
/// hesaplayamaz. Bu yüzden veri tek yönde akıyor: uygulama ölçer, ortak
/// kapsayıcıya yazar, widget okur.
///
/// Uygulama hiç açılmadıysa dosya da yoktur — widget o durumda kendi
/// okuyabildiği değerlere (bellek, disk, batarya) düşer.
struct SystemSnapshot: Codable, Sendable, Equatable {
    var date: Date = .distantPast
    var cpu = CPULoadStats()
    var memory = MemoryStats()
    var disk = DiskStats()
    var battery = BatteryStats()
    var network = NetworkStats()
    var device = DeviceStats()

    /// Uygulamada seçili dil. Uzantı kendi `UserDefaults`'ını görüyor,
    /// uygulamanınkini değil; dil tercihi de bu kanaldan geçiyor.
    var language: String = "en"

    /// Yaşlanmış bir anlık görüntü yanlış değil, eski: widget bunu
    /// "az önce" diye göstermemeli.
    var isStale: Bool {
        Date().timeIntervalSince(date) > 15 * 60
    }
}

/// Anlık görüntünün ortak kapsayıcıdaki dosyası.
///
/// Grup kimliği takım öneki taşıyor (`V793RH49BX.group…`): uygulama kum
/// havuzunda değil, uzantı ise zorunlu olarak kum havuzunda çalışıyor ve
/// macOS'ta iki tarafın aynı klasörü görebilmesinin tek yolu bu biçim.
enum SystemSnapshotStore {
    static let appGroupIdentifier = "V793RH49BX.group.com.dadebay.glassdo"

    private static let fileName = "system-snapshot.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    static func write(_ snapshot: SystemSnapshot) {
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    static func read() -> SystemSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(SystemSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}
