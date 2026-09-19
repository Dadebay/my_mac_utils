import Foundation

/// Ağ geçmişinin diskteki tek kaynağı: dosya okuma/yazma, v1→v2 göçü ve
/// `NetworkUsageAccumulator`'ın kendisi.
///
/// Hem ana uygulama (`NetworkHistoryStore`, `@MainActor`/`@Observable`
/// sarmalayıcı — UI'a yayınlanan değerler, widget debounce'u) hem de arka
/// plan ağ ajanı (`GlassDoNetworkAgent`, sade bir döngü) bu sınıfı
/// kullanıyor. İkisinin de aynı dosyayı **aynı anda** yazmaması şart —
/// aksi hâlde iki süreç birbirinin baseline'ının üstüne yazıp veriyi
/// bozabilir. Bu yüzden tasarım kuralı: ajan kayıtlıyken yalnız o yazar,
/// ana uygulama salt okur (bkz. `NetworkHistoryStore`'daki `agentOwnsWrites`).
final class NetworkHistoryPersistence {
    private(set) var accumulator: NetworkUsageAccumulator

    private var lastFlush = Date.distantPast
    private var needsFlush = false
    private let fileURL: URL?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let directory = base?.appendingPathComponent("GlassDo", isDirectory: true) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("network-history.json")
        } else {
            fileURL = nil
        }
        accumulator = NetworkUsageAccumulator()
        load()
    }

    // MARK: - Örnekleme

    /// Verilen (zaten fiziksel arayüzlere filtrelenmiş) örnekleri işler.
    /// Aynı baytların iki kez yazılmaması, çağıranın aynı süreç içinde
    /// `recordCurrentTraffic()`'i art arda kısa aralıkla çağırmaması —
    /// tekilleştirme burada değil, çağıranda (`NetworkHistoryStore`'daki
    /// tek zamanlayıcı, ya da ajanın tek döngüsü).
    @discardableResult
    func ingest(samples: [NetworkInterfaceSample], at date: Date) -> (received: UInt64, sent: UInt64) {
        let namesBefore = Set(accumulator.payload.baselines.keys)
        let delta = accumulator.ingest(samples: samples, at: date)
        // Yeni kurulan bir arayüz çizgisi de kalıcı olmalı — diske
        // yazılmazsa bir sonraki açılış "ilk örnek" sanır.
        if delta.received > 0 || delta.sent > 0
            || namesBefore != Set(accumulator.payload.baselines.keys) {
            needsFlush = true
        }
        flushIfNeeded()
        return delta
    }

    func windowTotals(now: Date) -> (today: UInt64, yesterday: UInt64, last7: UInt64, last30: UInt64) {
        (
            accumulator.total(overLastDays: 1, now: now),
            accumulator.dayTotal(offset: 1, now: now),
            accumulator.total(overLastDays: 7, now: now),
            accumulator.total(overLastDays: 30, now: now)
        )
    }

    func dailyTotals(days: Int, now: Date) -> [UInt64] {
        accumulator.dailyTotals(days: days, now: now)
    }

    // MARK: - Sıfırlama

    func reset(now: Date, samples: [NetworkInterfaceSample]) {
        accumulator.reset()
        accumulator.ingest(samples: samples, at: now)
        needsFlush = true
        flush()
    }

    // MARK: - Kalıcılık

    private static let flushInterval: TimeInterval = 30

    private func flushIfNeeded() {
        guard needsFlush, Date().timeIntervalSince(lastFlush) >= Self.flushInterval else { return }
        flush()
    }

    /// Paneli/uygulamayı kapatmadan önce çağrılabilir — son birkaç
    /// saniyelik trafik kaybolmasın.
    func flush() {
        guard let fileURL, needsFlush else { return }
        guard let data = try? JSONEncoder().encode(accumulator.payload) else { return }
        // Atomik: süreç yazmanın ortasında kapanırsa dosya yarım kalmaz.
        try? data.write(to: fileURL, options: .atomic)
        lastFlush = Date()
        needsFlush = false
    }

    /// Ajan yazdıktan sonra ana uygulamanın (salt okur modda) güncel
    /// toplamları görmesi için diskten yeniden okur.
    func reload() {
        load()
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(NetworkUsagePayload.self, from: data)
        else { return }

        let migrated = decoded.migratedToCurrentSchema(now: Date(), calendar: .current)
        accumulator = NetworkUsageAccumulator(payload: migrated)

        if migrated.schemaVersion != decoded.schemaVersion {
            needsFlush = true
            flush()
        }
    }
}
