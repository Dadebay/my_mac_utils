import Foundation

/// GlassDo widget'larının ve kısayollarının ne sıklıkla kullanıldığını,
/// tamamen bu Mac'te tutar.
///
/// Burada tutulan tek şey: hangi özellik, hangi günde, kaç kez. Görev
/// başlığı, dosya adı, IP adresi ya da kullanıcı kimliği yok — ve hiçbir
/// ağ isteği yok. `About` penceresindeki Kullanım bölümü dışında hiçbir
/// yere okunmuyor/gönderilmiyor.
///
/// Kalıcılık deseni `NetworkHistoryStore` ile aynı aileden: küçük, atomik
/// bir JSON dosyası, günlük kovalar. Fark: kullanım kayıtları saniyede bir
/// değil, kullanıcı gerçekten bir düğmeye bastığında oluşuyor — o yüzden
/// her kayıtta hemen diske yazmanın maliyeti önemsiz, ayrı bir "flush
/// aralığı" gerekmiyor.
actor UsageStore {
    static let shared = UsageStore()

    /// "Son yıl" penceresi 365 gün geriye bakabilsin diye bir miktar payla.
    private static let retentionDays = 400

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private struct Payload: Codable {
        var schemaVersion: Int = 1
        var days: [String: DailyUsageBucket] = [:]
        /// Günlük kovalar 400 günde budansa da hiç sıfırlanmayan toplam —
        /// "All Time" bunu okur.
        var allTimeCounts: [String: Int] = [:]
        var lastUsedFeature: String?
        var lastUsedDate: Date?
    }

    private var payload = Payload()
    private let fileURL: URL?

    /// Testler gerçek Application Support yerine geçici bir kök verebilsin
    /// diye — `ManagedStorageService` ile aynı desen.
    init(root: URL? = nil) {
        if let root {
            fileURL = root.appendingPathComponent("usage-stats.json")
        } else if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directory = base.appendingPathComponent("GlassDo", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("usage-stats.json")
        } else {
            fileURL = nil
        }

        // Bir actor'ın senkron `init`'i kendi isolation'ına bağlı değil —
        // başka bir isolated metodu (örn. `load()`) buradan çağıramaz.
        // Depolanan alanlara doğrudan atama ise serbest, o yüzden yükleme
        // burada elle tekrarlanıyor.
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            payload = decoded
        }
    }

    // MARK: - Kayıt

    /// Bir özelliğin bilinçli bir kullanıcı eylemiyle tetiklendiğini
    /// kaydeder. Görünüm yeniden çizimlerinden, WidgetKit zaman çizelgesi
    /// yenilemelerinden veya programatik seçimlerden **çağrılmamalı** —
    /// çağıran taraf bunun gerçek bir tıklama olduğunu garanti etmeli.
    func record(_ feature: UsageFeature, source: UsageSource, at date: Date = Date()) {
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        // Bozuk/gelecek tarihli bir kayıt istatistikleri saçmalaştırmasın.
        guard day <= today else { return }

        let key = Self.dayFormatter.string(from: day)
        var bucket = payload.days[key] ?? DailyUsageBucket()
        bucket[feature] += 1
        payload.days[key] = bucket

        payload.allTimeCounts[feature.rawValue, default: 0] += 1
        payload.lastUsedFeature = feature.rawValue
        payload.lastUsedDate = date

        prune(referenceDay: today)
        flush()
    }

    /// Yalnızca kullanım sayaçlarını siler. Görevler, klasörler ve
    /// uygulama ayarları bambaşka bir depoda (SwiftData / `UserDefaults`)
    /// olduğu için bu işlemden hiç etkilenmiyor.
    func reset() {
        payload = Payload()
        flush()
    }

    // MARK: - Okuma

    func snapshot(for period: UsagePeriod, now: Date = Date()) -> UsageSnapshot {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)

        let totals: [String: Int]
        let activeDays: Int

        if let window = period.dayWindow {
            var combined: [String: Int] = [:]
            var days = 0
            for offset in 0..<window {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let key = Self.dayFormatter.string(from: date)
                guard let bucket = payload.days[key] else { continue }
                if bucket.total > 0 { days += 1 }
                for (rawFeature, count) in bucket.counts {
                    combined[rawFeature, default: 0] += count
                }
            }
            totals = combined
            activeDays = days
        } else {
            totals = payload.allTimeCounts
            activeDays = payload.days.values.filter { $0.total > 0 }.count
        }

        let totalUses = totals.values.reduce(0, +)
        let mostUsed = totals
            .compactMap { key, count -> (UsageFeature, Int)? in
                guard let feature = UsageFeature(rawValue: key) else { return nil }
                return (feature, count)
            }
            .max { lhs, rhs in
                lhs.1 != rhs.1
                    ? lhs.1 < rhs.1
                    : Self.priority(lhs.0) > Self.priority(rhs.0)
            }?
            .0

        let widgetTotal = UsageFeature.allCases
            .filter(\.isWidget)
            .reduce(0) { $0 + (totals[$1.rawValue] ?? 0) }

        // Kullanılmamış widget'lar da satır olarak kalıyor (sayı sıfır) —
        // "Battery kaç defa, Processor kaç defa" sorusunun cevabı hiç
        // dokunulmamışlar için de görünür olmalı, yalnızca kullanılanlar
        // için değil.
        let features: [FeatureUsage] = UsageFeature.allCases
            .filter(\.isWidget)
            .map { feature -> FeatureUsage in
                let count = totals[feature.rawValue] ?? 0
                let fraction = widgetTotal > 0 ? Double(count) / Double(widgetTotal) : 0
                return FeatureUsage(feature: feature, count: count, fraction: fraction)
            }
            .sorted { lhs, rhs in
                lhs.count != rhs.count
                    ? lhs.count > rhs.count
                    : Self.priority(lhs.feature) < Self.priority(rhs.feature)
            }

        return UsageSnapshot(
            period: period,
            totalUses: totalUses,
            mostUsed: mostUsed,
            activeDays: activeDays,
            features: features,
            dailyTotals: recentDailyTotals(calendar: calendar, today: today),
            lastUsedFeature: payload.lastUsedFeature.flatMap(UsageFeature.init(rawValue:)),
            lastUsedDate: payload.lastUsedDate
        )
    }

    /// Dönemden bağımsız, her zaman son 7 günü gösteren mini grafiğin verisi.
    private func recentDailyTotals(calendar: Calendar, today: Date) -> [DayCount] {
        (0..<7).reversed().compactMap { offset -> DayCount? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Self.dayFormatter.string(from: date)
            return DayCount(day: date, total: payload.days[key]?.total ?? 0)
        }
    }

    /// Sayı eşitliğinde kararlı bir sıralama için `UsageFeature.allCases`
    /// içindeki bildirim sırası kullanılıyor.
    private static func priority(_ feature: UsageFeature) -> Int {
        UsageFeature.allCases.firstIndex(of: feature) ?? .max
    }

    // MARK: - Kalıcılık

    private func prune(referenceDay: Date) {
        guard payload.days.count > Self.retentionDays else { return }
        let calendar = Calendar.autoupdatingCurrent
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: referenceDay) else { return }
        let cutoffKey = Self.dayFormatter.string(from: cutoff)
        for key in payload.days.keys where key < cutoffKey {
            payload.days.removeValue(forKey: key)
        }
    }

    private func flush() {
        guard let fileURL, let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension UsageStore {
    /// Buton eylemleri gibi eşzamanlı yerlerden çağrılacak kısayol —
    /// `await` beklemeden ateşleyip unutur. Kayıt sırası önemli değil:
    /// `actor` her çağrıyı kendi sırasına göre serileştiriyor.
    nonisolated static func track(_ feature: UsageFeature, source: UsageSource) {
        _Concurrency.Task { await UsageStore.shared.record(feature, source: source) }
    }
}
