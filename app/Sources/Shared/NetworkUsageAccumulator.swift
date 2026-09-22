import Foundation
import os

/// Bir arayüzün en son görülen ham sayacı — bir sonraki örnekte fark almak
/// için başlangıç çizgisi.
struct NetworkInterfaceBaseline: Codable, Equatable, Sendable {
    var received: UInt64
    var sent: UInt64
    /// Gün sınırında ve kaybolan arayüzleri temizlerken gerekiyor: uzun
    /// süre görünmeyen bir arayüz geri geldiğinde eski çizgisine göre fark
    /// almak, aradaki bütün trafiği tek seferde bugüne yazardı.
    var lastSeen: Date
}

struct NetworkDayTotal: Codable, Equatable, Sendable {
    var received: UInt64 = 0
    var sent: UInt64 = 0

    var combined: UInt64 { received.saturatingAdding(sent) }
}

/// Diskte saklanan ağ geçmişi.
///
/// v1'de tek bir toplam başlangıç çizgisi (`lastRawReceived`/`lastRawSent`)
/// tutuluyordu. O şema arayüz değişimini modelleyemiyordu: VPN kapanıp
/// `utun*` arayüzü yok olunca toplam düşüyor, kod bunu "sayaç sıfırlandı"
/// sanıp o anki toplamın TAMAMINI (gigabaytlarca) bugüne ekliyordu.
struct NetworkUsagePayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int = currentSchemaVersion
    var days: [String: NetworkDayTotal] = [:]
    var baselines: [String: NetworkInterfaceBaseline] = [:]
    /// En son işlenen örneğin gün anahtarı. Gün değişince ilk örnek yalnız
    /// yeni çizgiyi kurar; iki güne yayılmış bir deltayı körlemesine tek güne
    /// yazmaktansa birkaç saniyeyi eksik saymak güvenli.
    var lastSampleDay: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, days, baselines, lastSampleDay
    }

    init() {}

    /// v1 JSON'unda `schemaVersion` hiç yoktu ve `days` dışındaki alanlar
    /// farklıydı; eksik alanlar varsayılana düşüyor, `lastRaw*` okunmuyor —
    /// o çizgi yeni şemaya çevrilemez (bkz. `migratedToCurrentSchema`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        days = try container.decodeIfPresent([String: NetworkDayTotal].self, forKey: .days) ?? [:]
        baselines = try container.decodeIfPresent(
            [String: NetworkInterfaceBaseline].self, forKey: .baselines
        ) ?? [:]
        lastSampleDay = try container.decodeIfPresent(String.self, forKey: .lastSampleDay)
    }

    /// v1 → v2 geçişi.
    ///
    /// Bugünün kovası siliniyor çünkü o toplamın ne kadarının sanal arayüz
    /// tekrar sayımı olduğu matematiksel olarak ayrılamaz. Önceki günler
    /// korunuyor: onlar da eski algoritmadan geliyor ama sessizce silmek
    /// kullanıcının bütün geçmişini yok etmek olurdu — tam sıfırlama açık
    /// onay ister (bkz. `NetworkHistoryStore.resetHistory`).
    func migratedToCurrentSchema(now: Date, calendar: Calendar) -> NetworkUsagePayload {
        guard schemaVersion < Self.currentSchemaVersion else { return self }

        var migrated = self
        migrated.schemaVersion = Self.currentSchemaVersion
        migrated.days.removeValue(forKey: NetworkUsageAccumulator.dayKey(for: now, calendar: calendar))
        // Eski toplam çizgi taşınamaz; ilk örnek yeni arayüz çizgilerini
        // kuracak ve delta üretmeyecek.
        migrated.baselines = [:]
        migrated.lastSampleDay = nil
        return migrated
    }
}

/// Ağ geçmişinin bütün aritmetiği. Saat, takvim ve arayüz örnekleri
/// dışarıdan veriliyor — hiçbir yerde `getifaddrs`, dosya ya da `Date()`
/// çağrısı yok, bu yüzden tamamen birim testiyle doğrulanabiliyor.
struct NetworkUsageAccumulator {
    private(set) var payload: NetworkUsagePayload
    private let calendar: Calendar

    /// Bu kadar gün görünmeyen arayüzün çizgisi atılır. Geri geldiğinde
    /// yeniden çizgi kurulur (delta 0) — aradaki, ölçemediğimiz trafiği
    /// uydurmaktansa eksik saymak doğru yön.
    private static let baselineRetentionDays = 2
    /// Diskteki en eski gün: 30 günlük pencere + pay.
    private static let dayRetentionDays = 35

    private static let logger = Logger(subsystem: "com.dadebay.GlassDo", category: "NetworkUsage")

    init(payload: NetworkUsagePayload = NetworkUsagePayload(), calendar: Calendar = .current) {
        self.payload = payload
        self.calendar = calendar
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        var formatter = Self.dayFormatter
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: calendar.startOfDay(for: date))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func dayKey(for date: Date) -> String {
        Self.dayKey(for: date, calendar: calendar)
    }

    // MARK: - Örnek işleme

    /// Verilen (zaten filtrelenmiş) arayüz örneklerini işler ve bu turda
    /// bugüne eklenen baytları döndürür.
    ///
    /// Her arayüz kendi çizgisiyle karşılaştırılıyor:
    /// 1. Hiç görülmemiş arayüz → yalnız çizgi kurulur, delta 0.
    /// 2. `raw >= çizgi` → yalnız fark eklenir.
    /// 3. `raw < çizgi` → sayaç sıfırlanmış sayılır, yeni çizgi kurulur,
    ///    delta 0. (Eski kod burada ham değerin tamamını ekliyordu.)
    @discardableResult
    mutating func ingest(
        samples: [NetworkInterfaceSample], at date: Date
    ) -> (received: UInt64, sent: UInt64) {
        let key = dayKey(for: date)
        // Gün değiştiyse bu örnek yalnız yeni günün çizgisini kurar.
        let crossedDayBoundary = payload.lastSampleDay != nil && payload.lastSampleDay != key

        var deltaReceived: UInt64 = 0
        var deltaSent: UInt64 = 0

        for sample in samples {
            if let baseline = payload.baselines[sample.name] {
                if sample.received >= baseline.received {
                    deltaReceived = deltaReceived.saturatingAdding(sample.received - baseline.received)
                }
                if sample.sent >= baseline.sent {
                    deltaSent = deltaSent.saturatingAdding(sample.sent - baseline.sent)
                }
            }

            payload.baselines[sample.name] = NetworkInterfaceBaseline(
                received: sample.received, sent: sample.sent, lastSeen: date
            )
        }

        payload.lastSampleDay = key

        guard !crossedDayBoundary else {
            pruneBaselines(now: date)
            pruneDays(now: date)
            return (0, 0)
        }

        if deltaReceived > 0 || deltaSent > 0 {
            var day = payload.days[key] ?? NetworkDayTotal()
            let (received, receivedOverflow) = day.received.addingReportingOverflow(deltaReceived)
            let (sent, sentOverflow) = day.sent.addingReportingOverflow(deltaSent)
            if receivedOverflow || sentOverflow {
                Self.logger.debug("Günlük ağ toplamı taşdı; değer tavanda tutuluyor (gün: \(key, privacy: .public))")
            }
            day.received = receivedOverflow ? .max : received
            day.sent = sentOverflow ? .max : sent
            payload.days[key] = day
        }

        pruneBaselines(now: date)
        pruneDays(now: date)
        return (deltaReceived, deltaSent)
    }

    // MARK: - Okuma

    func total(overLastDays days: Int, now: Date) -> UInt64 {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reduce(into: UInt64(0)) { sum, offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return }
            sum = sum.saturatingAdding(payload.days[dayKey(for: date)]?.combined ?? 0)
        }
    }

    func dayTotal(offset: Int, now: Date) -> UInt64 {
        let today = calendar.startOfDay(for: now)
        guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return 0 }
        return payload.days[dayKey(for: date)]?.combined ?? 0
    }

    /// Son `days` günün toplamları, en eskisi başta — grafik zamanı soldan
    /// sağa okusun.
    func dailyTotals(days: Int, now: Date) -> [UInt64] {
        (0..<days).reversed().map { dayTotal(offset: $0, now: now) }
    }

    // MARK: - Sıfırlama

    /// Bütün dönemleri ve arayüz çizgilerini siler. Çağıran taraf hemen
    /// ardından yeni çizgiyi kurmalı (`ingest`) — aksi hâlde sıfırlamadan
    /// sonraki ilk örnek açılıştan beri biriken her şeyi bugüne yazardı.
    mutating func reset() {
        payload = NetworkUsagePayload()
    }

    // MARK: - Budama

    private mutating func pruneBaselines(now: Date) {
        guard let cutoff = calendar.date(
            byAdding: .day, value: -Self.baselineRetentionDays, to: now
        ) else { return }
        payload.baselines = payload.baselines.filter { $0.value.lastSeen >= cutoff }
    }

    private mutating func pruneDays(now: Date) {
        guard payload.days.count > Self.dayRetentionDays else { return }
        guard let cutoff = calendar.date(
            byAdding: .day, value: -Self.dayRetentionDays, to: calendar.startOfDay(for: now)
        ) else { return }
        let cutoffKey = dayKey(for: cutoff)
        payload.days = payload.days.filter { $0.key >= cutoffKey }
    }
}

// MARK: - Widget anlık görüntüsü

enum NetworkUsageSnapshot {
    /// Widget'ın okuduğu anlık görüntüdeki ağ toplamlarını sıfırlar.
    /// Diğer alanlara (CPU, bellek, disk, batarya) dokunmuyor — onları
    /// uzantı zaten kendi ölçüp üzerine yazıyor.
    static func clearingNetworkTotals(in snapshot: SystemSnapshot) -> SystemSnapshot {
        var cleared = snapshot
        cleared.network.today = 0
        cleared.network.yesterday = 0
        cleared.network.last7Days = 0
        cleared.network.last30Days = 0
        cleared.network.dailyTotals = []
        return cleared
    }
}
