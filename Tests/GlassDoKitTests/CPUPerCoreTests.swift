import Testing
import Foundation

/// Çekirdek başına yük hesabı saf bir işlev: çekirdeğe hiç dokunmadan,
/// uydurulmuş sayaç değerleriyle sınanabiliyor. `host_processor_info`
/// çağrısının kendisi test edilemez (makineye göre değişir), ama asıl
/// hata yapılacak yer olan fark hesabı buradan geçiyor.
struct CPUPerCoreTests {

    private func core(
        user: UInt64 = 0,
        system: UInt64 = 0,
        nice: UInt64 = 0,
        idle: UInt64 = 0
    ) -> SystemSampler.CoreTicks {
        SystemSampler.CoreTicks(user: user, system: system, nice: nice, idle: idle)
    }

    @Test("İlk örnekte fark alınamadığı için bütün çekirdekler sıfır")
    func firstSampleIsZero() {
        let current = [core(user: 100, idle: 100), core(user: 500, idle: 20)]
        #expect(SystemSampler.perCoreUsage(from: [], to: current) == [0, 0])
    }

    @Test("Tek çekirdekte delta hesabı: (user + system + nice) / toplam")
    func singleCoreDelta() {
        let previous = core(user: 100, system: 50, nice: 10, idle: 400)
        // aktif fark = 30 + 10 + 10 = 50, boşta fark = 40, toplam = 90
        let current = core(user: 130, system: 60, nice: 20, idle: 440)

        let usage = SystemSampler.coreUsage(from: previous, to: current)
        #expect(abs(usage - 50.0 / 90.0) < 0.0001)
    }

    @Test("Çekirdek sırası korunuyor")
    func preservesCoreOrder() {
        let previous = [core(idle: 100), core(idle: 100), core(idle: 100)]
        // Her çekirdekte toplam fark 100 tik; aktif payı sırayla 25, 50, 75.
        let current = [
            core(user: 25, idle: 175),
            core(user: 50, idle: 150),
            core(user: 75, idle: 125),
        ]

        let usage = SystemSampler.perCoreUsage(from: previous, to: current)
        #expect(usage.count == 3)
        #expect(abs(usage[0] - 0.25) < 0.0001)
        #expect(abs(usage[1] - 0.50) < 0.0001)
        #expect(abs(usage[2] - 0.75) < 0.0001)
    }

    @Test("Yalnızca boşta duran çekirdek %0")
    func idleOnlyCoreIsZero() {
        let usage = SystemSampler.coreUsage(
            from: core(user: 10, idle: 1000),
            to: core(user: 10, idle: 2000)
        )
        #expect(usage == 0)
    }

    @Test("Hiç boşta kalmayan çekirdek %100")
    func fullyLoadedCoreIsOne() {
        let usage = SystemSampler.coreUsage(
            from: core(user: 100, system: 20, idle: 500),
            to: core(user: 400, system: 40, idle: 500)
        )
        #expect(usage == 1)
    }

    @Test("Toplam fark sıfırken (iki örnek arasında hiç tik yok) sonuç sıfır")
    func noElapsedTicksIsZero() {
        let sample = core(user: 100, system: 20, idle: 500)
        #expect(SystemSampler.coreUsage(from: sample, to: sample) == 0)
    }

    @Test("Sayaç geri sardığında sonuç güvenli kalıyor, taşma yok")
    func handlesCounterRollback() {
        // Uyku ya da sayaç sıfırlanması: yeni değer eskisinden küçük.
        // Çıkarma sarsaydı devasa bir aktif fark çıkar, çekirdek anında
        // %100 görünürdü.
        let usage = SystemSampler.coreUsage(
            from: core(user: 10_000, system: 5_000, nice: 100, idle: 90_000),
            to: core(user: 10, system: 5, nice: 0, idle: 90_100)
        )
        #expect(usage >= 0)
        #expect(usage <= 1)
        // Aktif farkların hepsi kırpıldı, yalnızca boşta artışı kaldı.
        #expect(usage == 0)
    }

    @Test("Önceki örnekte olmayan yeni çekirdek sıfır dönüyor")
    func unseenCoreIsZero() {
        let usage = SystemSampler.perCoreUsage(
            from: [core(idle: 100)],
            to: [core(user: 100, idle: 100), core(user: 50, idle: 50)]
        )
        #expect(usage.count == 2)
        #expect(usage[1] == 0)
    }

    @Test("Sonuçlar her durumda 0…1 aralığında")
    func staysInUnitRange() {
        let usage = SystemSampler.perCoreUsage(
            from: [core(user: 0, idle: 0)],
            to: [core(user: .max, idle: 0)]
        )
        #expect(usage.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    // MARK: - Codable geriye dönük uyumluluk

    @Test("Eski anlık görüntüde perCoreUsage yoksa boş dizi okunuyor")
    func decodesLegacySnapshotWithoutPerCoreUsage() throws {
        let json = Data(#"{"usage":0.42,"userUsage":0.3,"systemUsage":0.12,"coreCount":8}"#.utf8)

        let cpu = try JSONDecoder().decode(CPULoadStats.self, from: json)

        #expect(cpu.perCoreUsage.isEmpty)
        #expect(cpu.usage == 0.42)
        #expect(cpu.coreCount == 8)
        #expect(cpu.thermalPressure == .nominal)
    }

    @Test("Tamamen boş bir nesne bile varsayılanlarla çözülüyor")
    func decodesEmptyObject() throws {
        let cpu = try JSONDecoder().decode(CPULoadStats.self, from: Data("{}".utf8))
        #expect(cpu.perCoreUsage.isEmpty)
        #expect(cpu.usage == 0)
    }

    @Test("Yazılıp okunan perCoreUsage aynen geri geliyor")
    func roundTripsPerCoreUsage() throws {
        var stats = CPULoadStats()
        stats.perCoreUsage = [0.1, 0.9, 0.45]
        stats.coreCount = 3

        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(CPULoadStats.self, from: data)

        #expect(decoded.perCoreUsage == [0.1, 0.9, 0.45])
        #expect(decoded.coreCount == 3)
    }
}
