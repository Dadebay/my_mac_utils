import Foundation
import Testing

/// Ağ kullanımı toplayıcısının regresyon testleri.
///
/// Hepsi enjekte edilmiş saat, takvim ve arayüz örnekleriyle çalışıyor —
/// hiçbiri gerçek `getifaddrs` çağırmıyor ya da diske dokunmuyor.
struct NetworkUsageAccumulatorTests {

    // MARK: - Yardımcılar

    /// Saat dilimi sabit: gün sınırı testleri makinenin yerel saatine göre
    /// kaymasın.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private let megabyte: UInt64 = 1_000_000

    /// Ayakta ve çalışır durumdaki bir arayüz.
    private func sample(_ name: String, received: UInt64, sent: UInt64 = 0) -> NetworkInterfaceSample {
        NetworkInterfaceSample(
            name: name,
            received: received,
            sent: sent,
            flags: UInt32(IFF_UP) | UInt32(IFF_RUNNING)
        )
    }

    /// Yalnızca fiziksel arayüzler işlenir — gerçek çağrı yolunun aynısı
    /// (`NetworkInterfaceCounters.physicalSamples`).
    private func physical(_ samples: [NetworkInterfaceSample]) -> [NetworkInterfaceSample] {
        NetworkInterfacePolicy.physical(in: samples)
    }

    // MARK: - 1. VPN tekrar sayımı

    @Test("en0 ve utun0 aynı 100 MB'ı gösterdiğinde toplam 100 MB kalıyor")
    func vpnTrafficIsNotDoubleCounted() {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let now = date(2026, 6, 15)

        accumulator.ingest(
            samples: physical([sample("en0", received: 0), sample("utun0", received: 0)]),
            at: now
        )
        accumulator.ingest(
            samples: physical([
                sample("en0", received: 100 * megabyte),
                sample("utun0", received: 100 * megabyte),
            ]),
            at: now.addingTimeInterval(5)
        )

        #expect(accumulator.total(overLastDays: 1, now: now) == 100 * megabyte)
    }

    // MARK: - 2. Sanal arayüz filtresi

    @Test("Sanal ve tünel arayüzlerin artışı internet toplamına eklenmiyor")
    func virtualInterfacesAreExcluded() {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let now = date(2026, 6, 15)
        let virtualNames = ["awdl0", "llw0", "bridge0", "utun157"]

        accumulator.ingest(samples: physical(virtualNames.map { sample($0, received: 0) }), at: now)
        accumulator.ingest(
            samples: physical(virtualNames.map { sample($0, received: 500 * megabyte) }),
            at: now.addingTimeInterval(5)
        )

        #expect(accumulator.total(overLastDays: 1, now: now) == 0)
    }

    @Test("Filtre yalnızca ayakta olan fiziksel en* arayüzlerini geçiriyor")
    func policyAcceptsOnlyRunningEthernetInterfaces() {
        let up = UInt32(IFF_UP) | UInt32(IFF_RUNNING)

        #expect(NetworkInterfacePolicy.isPhysicalDataInterface(name: "en0", flags: up))
        #expect(NetworkInterfacePolicy.isPhysicalDataInterface(name: "en5", flags: up))

        for name in ["lo0", "utun0", "utun157", "ipsec0", "ppp0", "bridge0",
                     "awdl0", "llw0", "ap1", "p2p0", "gif0", "stf0", "anpi0"] {
            #expect(
                NetworkInterfacePolicy.isPhysicalDataInterface(name: name, flags: up) == false,
                "\(name) internet toplamına girmemeli"
            )
        }

        // Ayakta ama çalışmıyor, ya da hiç ayakta değil: sayaç durgun.
        #expect(NetworkInterfacePolicy.isPhysicalDataInterface(name: "en0", flags: UInt32(IFF_UP)) == false)
        #expect(NetworkInterfacePolicy.isPhysicalDataInterface(name: "en0", flags: 0) == false)
        // Geri döngü bayrağı taşıyan bir `en*` da elenmeli.
        #expect(
            NetworkInterfacePolicy.isPhysicalDataInterface(
                name: "en0", flags: up | UInt32(IFF_LOOPBACK)
            ) == false
        )
    }

    // MARK: - 3. İlk örnek

    @Test("İlk örnek yalnız çizgi kuruyor, bugün sıfır kalıyor")
    func firstSampleOnlyEstablishesBaseline() {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let now = date(2026, 6, 15)

        let delta = accumulator.ingest(
            samples: physical([sample("en0", received: 9 * 1024 * megabyte, sent: 3 * 1024 * megabyte)]),
            at: now
        )

        #expect(delta.received == 0)
        #expect(delta.sent == 0)
        #expect(accumulator.total(overLastDays: 1, now: now) == 0)
        #expect(accumulator.payload.baselines["en0"]?.received == 9 * 1024 * megabyte)
    }

    // MARK: - 4. Sayaç sıfırlanması

    @Test("Sayaç 500 MB'den 20 MB'ye düştüğünde delta sıfır oluyor")
    func counterResetDoesNotAddRawValue() {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let now = date(2026, 6, 15)

        accumulator.ingest(samples: physical([sample("en0", received: 0)]), at: now)
        accumulator.ingest(
            samples: physical([sample("en0", received: 500 * megabyte)]), at: now.addingTimeInterval(5)
        )
        let afterReset = accumulator.ingest(
            samples: physical([sample("en0", received: 20 * megabyte)]), at: now.addingTimeInterval(10)
        )

        #expect(afterReset.received == 0)
        // Sıfırlamadan önceki gerçek 500 MB duruyor, üstüne 20 MB eklenmiyor.
        #expect(accumulator.total(overLastDays: 1, now: now) == 500 * megabyte)
        // Yeni çizgi kuruldu: bundan sonrası düşük sayaçtan devam ediyor.
        #expect(accumulator.payload.baselines["en0"]?.received == 20 * megabyte)
    }

    // MARK: - 5. Arayüz değişimi

    @Test("en0 kaybolup en5 geldiğinde ilk en5 örneği delta üretmiyor")
    func newInterfaceProducesNoDelta() {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let now = date(2026, 6, 15)

        accumulator.ingest(samples: physical([sample("en0", received: 0)]), at: now)
        accumulator.ingest(
            samples: physical([sample("en0", received: 40 * megabyte)]), at: now.addingTimeInterval(5)
        )

        // Wi-Fi gitti, USB-Ethernet takıldı; sayacı çok daha yüksek.
        let delta = accumulator.ingest(
            samples: physical([sample("en5", received: 8 * 1024 * megabyte)]),
            at: now.addingTimeInterval(10)
        )

        #expect(delta.received == 0)
        #expect(accumulator.total(overLastDays: 1, now: now) == 40 * megabyte)
    }

    // MARK: - 6. Yeniden yükleme

    @Test("Payload tekrar yüklendiğinde yalnız yeni delta ekleniyor")
    func reloadedPayloadAddsOnlyNewDelta() {
        let now = date(2026, 6, 15)

        var first = NetworkUsageAccumulator(calendar: calendar)
        first.ingest(samples: physical([sample("en0", received: 100 * megabyte)]), at: now)
        first.ingest(
            samples: physical([sample("en0", received: 150 * megabyte)]), at: now.addingTimeInterval(5)
        )
        #expect(first.total(overLastDays: 1, now: now) == 50 * megabyte)

        // Uygulama kapandı, aynı payload diskten geri yüklendi.
        var reloaded = NetworkUsageAccumulator(payload: first.payload, calendar: calendar)
        reloaded.ingest(
            samples: physical([sample("en0", received: 170 * megabyte)]), at: now.addingTimeInterval(10)
        )

        // 50 (önce) + 20 (sonra) — 170'in tamamı değil.
        #expect(reloaded.total(overLastDays: 1, now: now) == 70 * megabyte)
    }

    // MARK: - 7. Gün sınırı

    @Test("Gün değişiminden sonraki ilk örnek çizgi kuruyor, dev delta oluşmuyor")
    func dayBoundaryFirstSampleRebaselines() {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let yesterday = date(2026, 6, 15, 23)
        let today = date(2026, 6, 16, 1)

        accumulator.ingest(samples: physical([sample("en0", received: 100 * megabyte)]), at: yesterday)
        accumulator.ingest(
            samples: physical([sample("en0", received: 120 * megabyte)]),
            at: yesterday.addingTimeInterval(5)
        )

        // Uyku boyunca 3 GB akmış; hangi kısmın hangi güne ait olduğu
        // bilinmiyor, o yüzden hiçbiri uydurulmuyor.
        let acrossMidnight = accumulator.ingest(
            samples: physical([sample("en0", received: 3 * 1024 * megabyte)]), at: today
        )

        #expect(acrossMidnight.received == 0)
        #expect(accumulator.dayTotal(offset: 0, now: today) == 0)
        #expect(accumulator.dayTotal(offset: 1, now: today) == 20 * megabyte)

        // Yeni günün sonraki örnekleri normal sayıyor.
        accumulator.ingest(
            samples: physical([sample("en0", received: 3 * 1024 * megabyte + 7 * megabyte)]),
            at: today.addingTimeInterval(5)
        )
        #expect(accumulator.dayTotal(offset: 0, now: today) == 7 * megabyte)
    }

    // MARK: - 8. Şema göçü

    @Test("Şema v1 fixture'ı okunuyor, bugün temizleniyor, önceki günler korunuyor")
    func schemaV1MigrationClearsTodayOnly() throws {
        let now = date(2026, 6, 15)
        let todayKey = NetworkUsageAccumulator.dayKey(for: now, calendar: calendar)
        let yesterdayKey = NetworkUsageAccumulator.dayKey(
            for: now.addingTimeInterval(-86_400), calendar: calendar
        )

        // Eski şema: schemaVersion yok, tek toplam çizgi var.
        let v1JSON = """
        {
          "days": {
            "\(todayKey)": { "received": 9660000000, "sent": 120000000 },
            "\(yesterdayKey)": { "received": 800000000, "sent": 40000000 }
          },
          "lastRawReceived": 12345678901,
          "lastRawSent": 2345678901
        }
        """

        let decoded = try JSONDecoder().decode(
            NetworkUsagePayload.self, from: Data(v1JSON.utf8)
        )
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.days.count == 2)

        let migrated = decoded.migratedToCurrentSchema(now: now, calendar: calendar)

        #expect(migrated.schemaVersion == NetworkUsagePayload.currentSchemaVersion)
        // Bozuk "bugün" gitti — hangi kısmının tekrar sayım olduğu ayrılamaz.
        #expect(migrated.days[todayKey] == nil)
        // Önceki gün sessizce silinmedi.
        #expect(migrated.days[yesterdayKey]?.received == 800_000_000)
        // Taşınamayan eski toplam çizgi kullanılmıyor.
        #expect(migrated.baselines.isEmpty)
        #expect(migrated.lastSampleDay == nil)

        // Göç sonrası ilk örnek yalnız çizgi kuruyor: bugün sıfırda kalıyor.
        var accumulator = NetworkUsageAccumulator(payload: migrated, calendar: calendar)
        accumulator.ingest(
            samples: physical([sample("en0", received: 12_345_678_901)]), at: now
        )
        #expect(accumulator.total(overLastDays: 1, now: now) == 0)
    }

    @Test("v2 payload yuvarlak gidip geliyor ve tekrar göç etmiyor")
    func schemaV2RoundTrips() throws {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let now = date(2026, 6, 15)
        accumulator.ingest(samples: physical([sample("en0", received: 10 * megabyte)]), at: now)
        accumulator.ingest(
            samples: physical([sample("en0", received: 30 * megabyte)]), at: now.addingTimeInterval(5)
        )

        let data = try JSONEncoder().encode(accumulator.payload)
        let decoded = try JSONDecoder().decode(NetworkUsagePayload.self, from: data)

        #expect(decoded == accumulator.payload)
        #expect(decoded.migratedToCurrentSchema(now: now, calendar: calendar) == decoded)
    }

    // MARK: - 9. Sıfırlama

    @Test("Sıfırlama bütün dönemleri ve arayüz çizgilerini siliyor")
    func resetClearsEveryPeriod() {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let now = date(2026, 6, 15)

        accumulator.ingest(samples: physical([sample("en0", received: 0)]), at: now)
        accumulator.ingest(
            samples: physical([sample("en0", received: 400 * megabyte)]), at: now.addingTimeInterval(5)
        )
        #expect(accumulator.total(overLastDays: 30, now: now) == 400 * megabyte)

        accumulator.reset()

        #expect(accumulator.total(overLastDays: 1, now: now) == 0)
        #expect(accumulator.total(overLastDays: 7, now: now) == 0)
        #expect(accumulator.total(overLastDays: 30, now: now) == 0)
        #expect(accumulator.payload.baselines.isEmpty)
        #expect(accumulator.dailyTotals(days: 30, now: now).allSatisfy { $0 == 0 })
    }

    @Test("Sıfırlama widget anlık görüntüsündeki ağ alanlarını da siliyor")
    func resetClearsWidgetSnapshotNetworkFields() {
        var snapshot = SystemSnapshot()
        snapshot.network.today = 9_660_000_000
        snapshot.network.yesterday = 800_000_000
        snapshot.network.last7Days = 20_000_000_000
        snapshot.network.last30Days = 60_000_000_000
        snapshot.network.dailyTotals = [1, 2, 3]
        snapshot.memory.total = 24 * 1024 * 1024 * 1024

        let cleared = NetworkUsageSnapshot.clearingNetworkTotals(in: snapshot)

        #expect(cleared.network.today == 0)
        #expect(cleared.network.yesterday == 0)
        #expect(cleared.network.last7Days == 0)
        #expect(cleared.network.last30Days == 0)
        #expect(cleared.network.dailyTotals.isEmpty)
        // Ağ dışındaki ölçümlere dokunulmuyor.
        #expect(cleared.memory.total == snapshot.memory.total)
    }

    // MARK: - 10. Çift tüketici

    @Test("Aynı örnek iki kez işlendiğinde baytlar iki kez yazılmıyor")
    func repeatedIngestOfSameSampleIsIdempotent() {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let now = date(2026, 6, 15)

        accumulator.ingest(samples: physical([sample("en0", received: 0)]), at: now)
        let samples = physical([sample("en0", received: 250 * megabyte)])

        // Panel ve arka plan zamanlayıcısı neredeyse aynı anda çağırıyor.
        let first = accumulator.ingest(samples: samples, at: now.addingTimeInterval(5))
        let second = accumulator.ingest(samples: samples, at: now.addingTimeInterval(5.1))

        #expect(first.received == 250 * megabyte)
        #expect(second.received == 0)
        #expect(accumulator.total(overLastDays: 1, now: now) == 250 * megabyte)
    }

    // MARK: - Taşma güvenliği

    @Test("Doymuş toplama taşmada sarmalamıyor")
    func saturatingAdditionDoesNotWrap() {
        #expect(UInt64.max.saturatingAdding(1) == .max)
        #expect(UInt64(10).saturatingAdding(5) == 15)
    }

    // MARK: - Çoklu fiziksel arayüz

    @Test("Aynı anda trafik taşıyan Wi-Fi ve Ethernet kendi deltalarıyla sayılıyor")
    func multiplePhysicalInterfacesEachCountOnce() {
        var accumulator = NetworkUsageAccumulator(calendar: calendar)
        let now = date(2026, 6, 15)

        accumulator.ingest(
            samples: physical([sample("en0", received: 0), sample("en5", received: 0)]), at: now
        )
        accumulator.ingest(
            samples: physical([
                sample("en0", received: 30 * megabyte),
                sample("en5", received: 12 * megabyte),
            ]),
            at: now.addingTimeInterval(5)
        )

        #expect(accumulator.total(overLastDays: 1, now: now) == 42 * megabyte)
    }
}
