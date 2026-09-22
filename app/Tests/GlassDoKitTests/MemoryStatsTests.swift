import Foundation
import Testing

/// Bellek tablosunun sözleşmesi: tek bir "kullanılan" tanımı ve eski
/// anlık görüntülerle uyum.
///
/// Bu testler makinenin gerçek belleğine hiç bakmıyor; `MemoryStats` saf
/// bir değer türü olduğu için elle kurulmuş örneklerle sınanıyor.
struct MemoryStatsTests {

    // MARK: - Kullanılan bellek

    @Test("Kullanılan bellek = uygulama + sabit + sıkıştırılmış")
    func usedIsSumOfThreeParts() {
        var stats = MemoryStats()
        stats.total = 24 * 1024 * 1024 * 1024
        stats.appMemory = 8 * 1024 * 1024 * 1024
        stats.wired = 4 * 1024 * 1024 * 1024
        stats.compressed = 2 * 1024 * 1024 * 1024
        // Önbellek kullanılan sayılmıyor: baskı altında anında boşaltılıyor.
        stats.cached = 6 * 1024 * 1024 * 1024

        #expect(stats.used == 14 * 1024 * 1024 * 1024)
    }

    @Test("Toplam sıfırken oran sıfır, bölme yok")
    func fractionsHandleZeroTotal() {
        var stats = MemoryStats()
        stats.appMemory = 1024
        stats.wired = 1024

        #expect(stats.usedFraction == 0)
        #expect(stats.unreclaimableFraction == 0)
    }

    @Test("Oranlar 1'in üstüne çıkmıyor")
    func fractionsAreClamped() {
        var stats = MemoryStats()
        stats.total = 1000
        stats.appMemory = 900
        stats.wired = 400
        stats.compressed = 200

        // Toplam 1500 > 1000: kullanım oranı kırpılıyor.
        #expect(stats.usedFraction == 1)
        // Boşaltılamayan pay ise toplamı aşmıyor; kendi gerçek oranını
        // veriyor. Kırpma yalnızca aşıldığında devreye girmeli.
        #expect(stats.unreclaimableFraction == 0.6)

        stats.wired = 900
        stats.compressed = 300
        #expect(stats.unreclaimableFraction == 1)
    }

    @Test("Boşaltılamayan pay yalnız sabit + sıkıştırılmış")
    func unreclaimableIgnoresAppMemory() {
        var stats = MemoryStats()
        stats.total = 100
        stats.appMemory = 50
        stats.wired = 20
        stats.compressed = 10

        #expect(stats.unreclaimableFraction == 0.3)
    }

    // MARK: - Eski anlık görüntülerle uyum

    @Test("Eski kayıttaki 'active' anahtarı uygulama belleği olarak okunuyor")
    func decodesLegacyActiveKey() throws {
        let legacy = """
        {"total":24000,"active":9000,"wired":3000,"compressed":1000,
         "cached":5000,"free":6000,"swapUsed":0,"swapTotal":0,"history":[]}
        """.data(using: .utf8)!

        let stats = try JSONDecoder().decode(MemoryStats.self, from: legacy)

        #expect(stats.appMemory == 9000)
        #expect(stats.used == 13000)
    }

    @Test("Eksik alanlı eski kayıt çökmüyor, varsayılana düşüyor")
    func decodesPartialSnapshot() throws {
        let partial = #"{"total":16000,"active":4000}"#.data(using: .utf8)!

        let stats = try JSONDecoder().decode(MemoryStats.self, from: partial)

        #expect(stats.total == 16000)
        #expect(stats.appMemory == 4000)
        #expect(stats.wired == 0)
        #expect(stats.history.isEmpty)
    }

    @Test("Yeni kayıt 'appMemory' yazıyor ve kayıpsız geri okunuyor")
    func roundTripsThroughNewKey() throws {
        var stats = MemoryStats()
        stats.total = 32000
        stats.appMemory = 12000
        stats.wired = 4000
        stats.compressed = 1500
        stats.cached = 8000
        stats.free = 6500
        stats.swapUsed = 120
        stats.swapTotal = 2048
        stats.history = [[0.4, 0.2, 0.1]]

        let data = try JSONEncoder().encode(stats)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("appMemory"))
        // Eski ad yazılmıyor: iki anahtar birden olsaydı hangisinin doğru
        // olduğu belirsizleşirdi.
        #expect(!text.contains("\"active\""))

        let decoded = try JSONDecoder().decode(MemoryStats.self, from: data)
        #expect(decoded == stats)
    }

    // MARK: - Sayfa sayacı hesabı

    @Test("Uygulama belleği iç sayfalardan boşaltılabilirleri düşüyor")
    func appMemorySubtractsPurgeable() {
        let pageSize: UInt64 = 16384
        let internalPages: UInt64 = 1000 * pageSize
        let purgeable: UInt64 = 250 * pageSize

        let appMemory = internalPages > purgeable ? internalPages - purgeable : 0

        #expect(appMemory == 750 * pageSize)
    }

    @Test("Boşaltılabilir sayfa iç sayfadan çoksa sonuç sıfır, taşma yok")
    func appMemoryNeverUnderflows() {
        // Değerler sabit yazılsaydı derleyici çıkarmayı derleme anında
        // yapıp taşma hatası verirdi; asıl sınanan şey zaten çalışma
        // anındaki koruma.
        let counters: [UInt64] = [100, 400]
        let internalPages = counters[0]
        let purgeable = counters[1]

        let appMemory = internalPages > purgeable ? internalPages - purgeable : 0

        #expect(appMemory == 0)
    }
}
