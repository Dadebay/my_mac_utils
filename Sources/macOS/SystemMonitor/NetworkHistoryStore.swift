import Darwin
import Foundation
import WidgetKit

/// Günlük ağ trafiğini diskte biriktirir.
///
/// Çekirdeğin arayüz sayaçları (`ifi_ibytes` / `ifi_obytes`) yalnızca son
/// açılıştan beri biriken toplamı verir ve her yeniden başlatmada sıfırlanır —
/// yani "son 30 gün" gibi bir değer sistemden okunamaz, uygulamanın kendisi
/// tarafından biriktirilmek zorundadır.
///
/// **İki mod:**
/// - Ağ ajanı (`GlassDoNetworkAgent`) kayıtlı değilken: bu sınıf kendi
///   örneklemesini yapar, tıpkı eskisi gibi — panel/menü çubuğu kapalıyken
///   de GlassDo çalıştığı sürece sayıyor, ama uygulama tamamen kapatılırsa
///   (Cmd+Q) geçmiş donuyor.
/// - Ajan kayıtlıyken: ajan `launchd` üzerinden GlassDo'nun kendisi
///   kapatılsa bile arka planda çalışmaya devam edip TEK yazıcı olarak
///   dosyayı güncelliyor. Bu durumda burası kendi başına örneklemeyi
///   bırakıp yalnızca diskten okuyor — iki sürecin aynı dosyaya aynı anda
///   yazıp birbirinin baseline'ının üstüne yazması (veri bozulması)
///   böylece hiç mümkün olmuyor.
@MainActor
final class NetworkHistoryStore {
    static let shared = NetworkHistoryStore()

    /// Geçmiş için saniyede bir örneklemeye gerek yok; toplamı etkilemeyecek
    /// kadar sık, uyandırma maliyeti önemsiz olacak kadar seyrek. Ajan
    /// modunda da aynı aralıkla diskten yeniden okunuyor — ajanın kendi
    /// örnekleme aralığıyla aynı, UI birkaç saniyeden fazla gecikmesin diye.
    private static let sampleInterval: Duration = .seconds(5)

    private var samplingTask: _Concurrency.Task<Void, Never>?
    private let persistence = NetworkHistoryPersistence()

    /// Bu süreç ajanın yazdığı dosyayı okuyor mu, yoksa kendisi mi yazıyor.
    /// Her turda `NetworkAgentSettings.isEnabled`'a bakmak yeterince ucuz
    /// (yerel `UserDefaults` okuma) — ayrı bir gözlemciye gerek yok.
    private var agentOwnsWrites: Bool { NetworkAgentSettings.isEnabled }

    /// Uygulama açılışında bir kez çağrılır.
    func startSampling() {
        guard samplingTask == nil else { return }
        _ = recordCurrentTraffic()
        samplingTask = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(for: Self.sampleInterval)
                guard !_Concurrency.Task.isCancelled else { return }
                _ = self?.recordCurrentTraffic()
            }
        }
    }

    /// Ajan modunda yalnızca diskten yeniden okur; kendi kendine
    /// örneklemez. Değilse çekirdek sayaçlarını okuyup geçmişe işler.
    /// Her iki modda da güncel pencere toplamlarını döndürür.
    @discardableResult
    func recordCurrentTraffic() -> (today: UInt64, last7: UInt64, last30: UInt64) {
        let now = Date()

        if agentOwnsWrites {
            persistence.reload()
        } else {
            persistence.ingest(samples: NetworkInterfaceCounters.physicalSamples(), at: now)
            // Widget'a taşımak da yazıcının işi — ajan kayıtlıyken bunu
            // zaten kendisi yapıyor (bkz. GlassDoNetworkAgent/main.swift).
            publishToWidgetIfNeeded()
        }

        let windows = persistence.windowTotals(now: now)
        return (windows.today, windows.last7, windows.last30)
    }

    /// Görünümün, yeni bir örnek işlemeden mevcut toplamları okuması için.
    var windowTotals: (today: UInt64, yesterday: UInt64, last7: UInt64, last30: UInt64) {
        persistence.windowTotals(now: Date())
    }

    /// Son `days` günün günlük toplamları, en eskisi başta — çubuk grafiği
    /// zamanı soldan sağa okusun.
    func dailyTotals(days: Int) -> [UInt64] {
        persistence.dailyTotals(days: days, now: Date())
    }

    // MARK: - Sıfırlama

    /// Kullanıcının onayladığı tam sıfırlama: bütün günler, arayüz
    /// çizgileri ve widget'ın gördüğü ağ toplamları sıfırlanır.
    ///
    /// Hemen yeni çizgi kuruluyor — aksi hâlde sıfırlamadan sonraki ilk
    /// örnek makinenin açılışından beri biriken her şeyi bugüne yazardı.
    /// Uygulamayı yeniden başlatmak gerekmiyor. Ajan kayıtlıyken de bu
    /// eylem doğrudan uygulamadan yürütülüyor — nadir, bilinçli bir
    /// kullanıcı eylemi olduğu için ajanın bir sonraki örneğiyle çok kısa
    /// bir yarış payı kabul edilebilir.
    func resetHistory() {
        persistence.reset(now: Date(), samples: NetworkInterfaceCounters.physicalSamples())

        let cleared = NetworkUsageSnapshot.clearingNetworkTotals(
            in: SystemSnapshotStore.read() ?? SystemSnapshot()
        )
        SystemSnapshotStore.write(cleared)
        lastWidgetPublish = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// `SystemStatsController`, widget'ın okuduğu dosyaya yalnızca en az bir
    /// tüketici (panel/menü çubuğu) açıkken yazıyor. Bu ikisi kapalı kalırsa
    /// widget hiç güncellenmez ve "bugün" toplamı, uygulama ölçmeye devam
    /// etse bile ekranda saatler öncesinden donmuş kalır. Bu yüzden ağ
    /// toplamları, tüketiciden bağımsız olarak da — bu sınıfın kendi arka
    /// plan örneklemesinden — düzenli aralıklarla widget'a taşınıyor.
    private static let widgetPublishInterval: TimeInterval = 5 * 60
    private var lastWidgetPublish = Date.distantPast

    private func publishToWidgetIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastWidgetPublish) >= Self.widgetPublishInterval else { return }
        lastWidgetPublish = now

        var snapshot = SystemSnapshotStore.read() ?? SystemSnapshot()
        let windows = windowTotals
        snapshot.date = now
        snapshot.network.today = windows.today
        snapshot.network.yesterday = windows.yesterday
        snapshot.network.last7Days = windows.last7
        snapshot.network.last30Days = windows.last30
        snapshot.network.dailyTotals = dailyTotals(days: 30)

        SystemSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Panel kapanırken çağrılır — son birkaç saniyelik trafik kaybolmasın.
    /// Ajan modunda hiçbir şey biriktirmediğimiz için (`ingest` hiç
    /// çağrılmadı) bu zararsız bir no-op'a düşer.
    func flush() {
        persistence.flush()
    }
}
