import Foundation
import Testing

/// `UsageStore`'un testleri.
///
/// Hepsi geçici bir kök dizinde çalışıyor: hiçbir test kullanıcının
/// gerçek Application Support klasörüne dokunmuyor. Servisin kökü
/// dışarıdan alması zaten bunun için (bkz. `ManagedStorageTests`).
struct UsageStoreTests {

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassDoUsageTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.autoupdatingCurrent.date(from: components)!
    }

    // MARK: - Temel kayıt

    @Test("İlk kayıt doğru özelliği bir artırıyor")
    func firstRecordIncrementsFeature() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)

        await store.record(.network, source: .edgeRail)

        let snapshot = await store.snapshot(for: .allTime)
        #expect(snapshot.totalUses == 1)
        #expect(snapshot.features.first?.feature == .network)
        #expect(snapshot.features.first?.count == 1)
    }

    @Test("Aynı gün kayıtları aynı kovada toplanıyor")
    func sameDayRecordsAccumulate() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)
        let day = date(2026, 3, 10)

        await store.record(.memory, source: .edgeRail, at: day.addingTimeInterval(60 * 60))
        await store.record(.memory, source: .edgeRail, at: day.addingTimeInterval(60 * 60 * 5))
        await store.record(.memory, source: .mainWindow, at: day.addingTimeInterval(60 * 60 * 9))

        let snapshot = await store.snapshot(for: .allTime, now: day)
        #expect(snapshot.totalUses == 3)
        #expect(snapshot.features.first(where: { $0.feature == .memory })?.count == 3)
        #expect(snapshot.activeDays == 1)
    }

    @Test("Gün değişince yeni bir kova açılıyor")
    func newDayCreatesNewBucket() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)
        let dayOne = date(2026, 3, 10)
        let dayTwo = date(2026, 3, 11)

        await store.record(.disk, source: .edgeRail, at: dayOne)
        await store.record(.disk, source: .edgeRail, at: dayTwo)

        let snapshot = await store.snapshot(for: .last7Days, now: dayTwo)
        #expect(snapshot.activeDays == 2)
        #expect(snapshot.features.first(where: { $0.feature == .disk })?.count == 2)
    }

    // MARK: - Dönem filtreleri

    @Test("7 / 30 / 365 günlük pencereler sınırında doğru kesiyor")
    func periodWindowsAreExact() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)
        let now = date(2026, 6, 15)
        let calendar = Calendar.autoupdatingCurrent

        // Tam sınırda (dahil) ve sınırın bir gün dışında (hariç) kayıtlar.
        func offset(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now)!
        }

        await store.record(.network, source: .edgeRail, at: offset(6))   // son 7 gün: dahil
        await store.record(.battery, source: .edgeRail, at: offset(7))   // son 7 gün: hariç
        await store.record(.disk, source: .edgeRail, at: offset(29))     // son 30 gün: dahil
        await store.record(.processor, source: .edgeRail, at: offset(30)) // son 30 gün: hariç
        await store.record(.folders, source: .edgeRail, at: offset(364)) // son yıl: dahil
        await store.record(.memory, source: .edgeRail, at: offset(365))  // son yıl: hariç

        // `features` artık kullanılmamış widget'ları da sıfır sayıyla
        // listeliyor (bkz. `UsageBarRow` — "Battery kaç defa?" sorusunun
        // cevabı hiç dokunulmamışsa da görünmeli), o yüzden dönemin dışında
        // kalan bir kayıt "listede yok" değil "sayısı sıfır" olarak kontrol
        // ediliyor.
        func count(_ snapshot: UsageSnapshot, _ feature: UsageFeature) -> Int {
            snapshot.features.first(where: { $0.feature == feature })?.count ?? 0
        }

        let last7 = await store.snapshot(for: .last7Days, now: now)
        #expect(count(last7, .network) == 1)
        #expect(count(last7, .battery) == 0)

        let last30 = await store.snapshot(for: .last30Days, now: now)
        #expect(count(last30, .disk) == 1)
        #expect(count(last30, .processor) == 0)

        let lastYear = await store.snapshot(for: .lastYear, now: now)
        #expect(count(lastYear, .folders) == 1)
        #expect(count(lastYear, .memory) == 0)
    }

    // MARK: - Kalıcı toplamlar

    @Test("All-time toplamı, günlük kovalar budansa da kaybolmuyor")
    func allTimeSurvivesPruning() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)
        let calendar = Calendar.autoupdatingCurrent
        let now = date(2026, 6, 15)

        // Saklama sınırının (400 gün) ötesine geçecek kadar farklı günde
        // birer kayıt — en eski kova budandığında bile all-time toplam
        // hâlâ tam sayıyı vermeli.
        for offset in 0...400 {
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            await store.record(.tasks, source: .edgeRail, at: day)
        }

        let snapshot = await store.snapshot(for: .allTime, now: now)
        #expect(snapshot.totalUses == 401)
        #expect(snapshot.features.first(where: { $0.feature == .tasks })?.count == 401)
    }

    // MARK: - Takvim günü sınırı (DST/saat dilimi güvenliği)

    @Test("Aynı yerel takvim gününün başı ve sonu aynı kovaya düşüyor")
    func sameCalendarDayBucketsTogether() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)
        let day = date(2026, 3, 10)
        let earlyMorning = date(2026, 3, 10, hour: 0)
        let lateNight = date(2026, 3, 10, hour: 23)

        await store.record(.pinMode, source: .edgeRail, at: earlyMorning)
        await store.record(.pinMode, source: .edgeRail, at: lateNight)

        let snapshot = await store.snapshot(for: .allTime, now: day)
        #expect(snapshot.activeDays == 1)
    }

    // MARK: - Bozuk depolama

    @Test("Bozuk dosya çökme yerine boş duruma dönüyor")
    func corruptStorageFallsBackToEmpty() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("usage-stats.json")
        try Data("bu geçerli bir JSON değil { { {".utf8).write(to: fileURL)

        let store = UsageStore(root: root)
        let snapshot = await store.snapshot(for: .allTime)

        #expect(snapshot.isEmpty)
        #expect(snapshot.totalUses == 0)
    }

    // MARK: - Eşzamanlılık

    @Test("Eşzamanlı kayıtlar kaybolmuyor")
    func concurrentRecordsDoNotLoseIncrements() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask { await store.record(.quickAdd, source: .edgeRail) }
            }
        }

        let snapshot = await store.snapshot(for: .allTime)
        #expect(snapshot.totalUses == 200)
    }

    // MARK: - Sıfırlama

    @Test("Sıfırlama yalnızca kullanım verisini siliyor")
    func resetClearsOnlyUsageData() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)

        await store.record(.network, source: .edgeRail)
        await store.record(.battery, source: .edgeRail)
        await store.reset()

        let snapshot = await store.snapshot(for: .allTime)
        #expect(snapshot.isEmpty)
        #expect(snapshot.lastUsedFeature == nil)
    }

    // MARK: - Gelecek tarihli kayıtlar

    @Test("Gelecek tarihli kayıtlar sayılmıyor")
    func futureDatedRecordsAreIgnored() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)

        await store.record(.network, source: .edgeRail, at: Date().addingTimeInterval(60 * 60 * 24 * 30))

        let snapshot = await store.snapshot(for: .allTime)
        #expect(snapshot.totalUses == 0)
    }

    // MARK: - Sıralama

    @Test("Eşit kullanımda sıralama bildirim sırasına göre deterministik")
    func tiesBreakDeterministically() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageStore(root: root)
        let now = date(2026, 6, 15)

        // `UsageFeature` bildirim sırasında disk, processor'dan önce gelir.
        await store.record(.processor, source: .edgeRail, at: now)
        await store.record(.disk, source: .edgeRail, at: now)

        let snapshot = await store.snapshot(for: .allTime, now: now)
        let order = snapshot.features.map(\.feature)
        let diskIndex = try #require(order.firstIndex(of: .disk))
        let processorIndex = try #require(order.firstIndex(of: .processor))
        #expect(diskIndex < processorIndex)
    }
}
