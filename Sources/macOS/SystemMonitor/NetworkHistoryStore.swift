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
/// Bunun kaçınılmaz sonucu: geçmiş yalnızca GlassDo çalışırken dolar,
/// geriye dönük doldurulamaz.
///
/// Bu yüzden örnekleme görünüme değil uygulamanın ömrüne bağlı: paylaşılan
/// örnek uygulama açılışında başlatılır ve panel kapalıyken de saymayı
/// sürdürür. Görünüme bağlansaydı "Bugün" yalnızca kullanıcının ekrana
/// baktığı saniyeleri sayardı.
///
/// Bu tip yalnızca kenar etkilerini taşıyor: zamanlayıcı, dosya, widget.
/// Bütün aritmetik `NetworkUsageAccumulator`'da ve orası saat/örnek enjekte
/// edilebildiği için birim testiyle doğrulanıyor.
@MainActor
final class NetworkHistoryStore {
    static let shared = NetworkHistoryStore()

    /// Geçmiş için saniyede bir örneklemeye gerek yok; toplamı etkilemeyecek
    /// kadar sık, uyandırma maliyeti önemsiz olacak kadar seyrek.
    private static let sampleInterval: Duration = .seconds(5)

    private var samplingTask: _Concurrency.Task<Void, Never>?

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

    /// Çekirdek sayaçlarını okuyup geçmişe işler; güncel pencere
    /// toplamlarını döndürür.
    ///
    /// Aynı baytlar iki kez yazılmaz: her arayüzün çizgisi bu çağrıda
    /// güncelleniyor, dolayısıyla panel ve arka plan zamanlayıcısı art arda
    /// çağırsa bile ikincisinin deltası sıfır çıkar.
    @discardableResult
    func recordCurrentTraffic() -> (today: UInt64, last7: UInt64, last30: UInt64) {
        let now = Date()
        // Arayüz kümesinin değişmesi de kalıcı olmalı: yeni kurulan bir
        // çizgi diske yazılmazsa her açılış "ilk örnek" sanılır ve iki
        // açılış arasındaki trafik sessizce kaybolur.
        let namesBefore = Set(accumulator.payload.baselines.keys)
        let delta = accumulator.ingest(samples: NetworkInterfaceCounters.physicalSamples(), at: now)
        if delta.received > 0 || delta.sent > 0
            || namesBefore != Set(accumulator.payload.baselines.keys) {
            needsFlush = true
        }
        flushIfNeeded()
        publishToWidgetIfNeeded()
        return (
            accumulator.total(overLastDays: 1, now: now),
            accumulator.total(overLastDays: 7, now: now),
            accumulator.total(overLastDays: 30, now: now)
        )
    }

    /// Görünümün, yeni bir örnek işlemeden mevcut toplamları okuması için.
    var windowTotals: (today: UInt64, yesterday: UInt64, last7: UInt64, last30: UInt64) {
        let now = Date()
        return (
            accumulator.total(overLastDays: 1, now: now),
            accumulator.dayTotal(offset: 1, now: now),
            accumulator.total(overLastDays: 7, now: now),
            accumulator.total(overLastDays: 30, now: now)
        )
    }

    /// Son `days` günün günlük toplamları, en eskisi başta — çubuk grafiği
    /// zamanı soldan sağa okusun.
    func dailyTotals(days: Int) -> [UInt64] {
        accumulator.dailyTotals(days: days, now: Date())
    }

    // MARK: - Sıfırlama

    /// Kullanıcının onayladığı tam sıfırlama: bütün günler, arayüz
    /// çizgileri ve widget'ın gördüğü ağ toplamları sıfırlanır.
    ///
    /// Hemen yeni çizgi kuruluyor — aksi hâlde sıfırlamadan sonraki ilk
    /// örnek makinenin açılışından beri biriken her şeyi bugüne yazardı.
    /// Uygulamayı yeniden başlatmak gerekmiyor.
    func resetHistory() {
        accumulator.reset()
        // Çizgiyi kur: bu ilk örnek tanım gereği delta üretmez.
        accumulator.ingest(samples: NetworkInterfaceCounters.physicalSamples(), at: Date())

        needsFlush = true
        flush()

        let cleared = NetworkUsageSnapshot.clearingNetworkTotals(
            in: SystemSnapshotStore.read() ?? SystemSnapshot()
        )
        SystemSnapshotStore.write(cleared)
        lastWidgetPublish = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Diskteki en eski kayıt: 30 günlük pencere + bir miktar pay.
    /// Her örnekte dosyaya yazmak gereksiz; bu aralıkta bir kez boşaltılır.
    private static let flushInterval: TimeInterval = 30

    private var accumulator = NetworkUsageAccumulator()
    private var lastFlush = Date.distantPast
    private var needsFlush = false

    /// `SystemStatsController`, widget'ın okuduğu dosyaya yalnızca en az bir
    /// tüketici (panel/menü çubuğu) açıkken yazıyor. Bu ikisi kapalı kalırsa
    /// widget hiç güncellenmez ve "bugün" toplamı, uygulama ölçmeye devam
    /// etse bile ekranda saatler öncesinden donmuş kalır. Bu yüzden ağ
    /// toplamları, tüketiciden bağımsız olarak da — bu sınıfın kendi arka
    /// plan örneklemesinden — düzenli aralıklarla widget'a taşınıyor.
    private static let widgetPublishInterval: TimeInterval = 5 * 60
    private var lastWidgetPublish = Date.distantPast

    private let fileURL: URL?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let directory = base?.appendingPathComponent("GlassDo", isDirectory: true) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("network-history.json")
        } else {
            fileURL = nil
        }
        load()
    }

    // MARK: - Widget'a bırakılan anlık görüntü

    /// Diğer alanlara (CPU, bellek, disk, batarya) dokunmuyor — onları
    /// widget uzantısı zaten kendi başına ölçüp üzerine yazıyor
    /// (`SystemProvider.current()`). Yalnızca uygulamanın kendi başına
    /// hesaplayamadığı ağ toplamları burada güncelleniyor.
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

    // MARK: - Kalıcılık

    private func flushIfNeeded() {
        guard needsFlush, Date().timeIntervalSince(lastFlush) >= Self.flushInterval else { return }
        flush()
    }

    /// Panel kapanırken çağrılır — son birkaç saniyelik trafik kaybolmasın.
    func flush() {
        guard let fileURL, needsFlush else { return }
        guard let data = try? JSONEncoder().encode(accumulator.payload) else { return }
        // Atomik: uygulama yazmanın ortasında kapanırsa dosya yarım kalmaz.
        try? data.write(to: fileURL, options: .atomic)
        lastFlush = Date()
        needsFlush = false
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(NetworkUsagePayload.self, from: data)
        else { return }

        let migrated = decoded.migratedToCurrentSchema(now: Date(), calendar: .current)
        accumulator = NetworkUsageAccumulator(payload: migrated)

        // Şema yükseldiyse hemen ve atomik olarak yaz: bir sonraki açılış
        // eski bozuk "bugün" toplamını tekrar görmesin.
        if migrated.schemaVersion != decoded.schemaVersion {
            needsFlush = true
            flush()
        }
    }
}
