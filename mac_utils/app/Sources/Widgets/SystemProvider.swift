import Foundation
import WidgetKit

/// Widget'ın bir yenilemede gösterdiği ölçüm.
struct SystemEntry: TimelineEntry {
    let date: Date
    let snapshot: SystemSnapshot

    var strings: WidgetStrings { WidgetStrings(language: snapshot.language) }

    /// Uygulama uzun süredir ölçüm bırakmadıysa geçmişe dayalı alanlar
    /// (ağ toplamları, sıcaklık) eskimiş olabilir.
    var isStale: Bool { snapshot.isStale }
}

/// Widget'ın verisi iki kaynaktan birleşiyor:
///
/// - **Uygulamanın bıraktığı anlık görüntü** — grafik geçmişi, ağ günlük
///   toplamları ve sıcaklık. Bunları uzantı kendi başına üretemez: geçmiş
///   zaman ister, sıcaklık sensörleri ise kum havuzundan görünmüyor.
/// - **Uzantının kendi ölçümü** — bellek, disk, batarya, çalışma süresi.
///   Bunlar tek örnekle okunabildiği için uygulama kapalıyken bile taze
///   kalıyorlar.
///
/// Böylece GlassDo hiç çalışmıyorken de widget ölü bir kart göstermiyor.
struct SystemProvider: TimelineProvider {
    /// WidgetKit'in yenileme bütçesi günlük ve sınırlı; beş dakika, sistem
    /// izleyici bir widget için gerçekçi en sık aralık.
    private static let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> SystemEntry {
        SystemEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SystemEntry) -> Void) {
        // Galeri önizlemesinde gerçek ölçüm beklenmemeli: kart hemen
        // çizilebilsin diye örnek veri veriliyor.
        if context.isPreview {
            completion(SystemEntry(date: Date(), snapshot: .placeholder))
            return
        }
        completion(SystemEntry(date: Date(), snapshot: Self.current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SystemEntry>) -> Void) {
        let entry = SystemEntry(date: Date(), snapshot: Self.current())
        completion(
            Timeline(
                entries: [entry],
                policy: .after(Date().addingTimeInterval(Self.refreshInterval))
            )
        )
    }

    /// Anlık görüntüyü uzantının kendi okuyabildikleriyle tazeler.
    /// Her ölçüm ayrı ayrı doğrulanıyor: kum havuzu birini engellerse
    /// yalnızca o alan anlık görüntüdeki hâliyle kalsın, kart komple
    /// boşalmasın.
    static func current() -> SystemSnapshot {
        var snapshot = SystemSnapshotStore.read() ?? SystemSnapshot()

        let memory = SystemSampler.memoryStats()
        if memory.total > 0 {
            snapshot.memory = memory.carryingHistory(from: snapshot.memory)
        }

        let disk = SystemSampler.diskStats()
        if disk.total > 0 {
            snapshot.disk = disk.carryingHistory(from: snapshot.disk)
        }

        let battery = SystemSampler.batteryStats()
        if battery.isPresent {
            snapshot.battery = battery.carryingHistory(from: snapshot.battery)
        }

        snapshot.device = SystemSampler.deviceStats()
        snapshot.cpu = refreshedCPU(from: snapshot.cpu)

        return snapshot
    }

    /// İşlemci yükü iki örnek arasındaki farktır; tek okumayla
    /// hesaplanamaz. Kısa bir aralıkla iki kez örnekleniyor — widget
    /// yenilemesi zaten saniyeler mertebesinde çalışabiliyor.
    private static func refreshedCPU(from previous: CPULoadStats) -> CPULoadStats {
        var cpu = previous
        cpu.coreCount = ProcessInfo.processInfo.processorCount
        cpu.thermalPressure = SystemSampler.thermalPressure()

        // Sensörler kum havuzundan okunamayabilir; o durumda uygulamanın
        // bıraktığı son değer korunuyor.
        if let temperature = CPUTemperature.current() {
            cpu.temperature = temperature
        }

        guard let first = SystemSampler.cpuTicks() else { return cpu }
        Thread.sleep(forTimeInterval: 0.4)
        guard let second = SystemSampler.cpuTicks(),
              let usage = SystemSampler.cpuUsage(from: first, to: second)
        else { return cpu }

        cpu.userUsage = usage.user
        cpu.systemUsage = usage.system
        cpu.usage = min(usage.user + usage.system, 1)
        return cpu
    }
}

// MARK: - Geçmişi koruyarak tazeleme

private extension MemoryStats {
    func carryingHistory(from old: MemoryStats) -> MemoryStats {
        var next = self
        next.history = old.history
        return next
    }
}

private extension DiskStats {
    func carryingHistory(from old: DiskStats) -> DiskStats {
        var next = self
        next.history = old.history
        return next
    }
}

private extension BatteryStats {
    func carryingHistory(from old: BatteryStats) -> BatteryStats {
        var next = self
        next.healthHistory = old.healthHistory
        return next
    }
}

// MARK: - Galeri önizlemesi

extension SystemSnapshot {
    /// Widget galerisinde ve yer tutucuda gösterilen örnek. Gerçekçi ama
    /// uydurma olduğu belli değerler: galeri kartı ölçüm beklerken boş
    /// görünmesin.
    static var placeholder: SystemSnapshot {
        var snapshot = SystemSnapshot()
        snapshot.date = Date()

        snapshot.cpu.usage = 0.24
        snapshot.cpu.userUsage = 0.17
        snapshot.cpu.systemUsage = 0.07
        snapshot.cpu.coreCount = 10
        snapshot.cpu.temperature = 46
        snapshot.cpu.history = (0..<34).map { _ in Double.random(in: 0.05...0.6) }
        snapshot.cpu.temperatureHistory = (0..<34).map { _ in Double.random(in: 38...58) }

        snapshot.memory.total = 32 * 1024 * 1024 * 1024
        snapshot.memory.active = 12 * 1024 * 1024 * 1024
        snapshot.memory.wired = 4 * 1024 * 1024 * 1024
        snapshot.memory.compressed = 1 * 1024 * 1024 * 1024

        snapshot.disk.volumeName = "Macintosh HD"
        snapshot.disk.total = 994_000_000_000
        snapshot.disk.used = 348_000_000_000
        snapshot.disk.history = (0..<34).map { _ in Double.random(in: 0.3...0.36) }

        snapshot.battery.isPresent = true
        snapshot.battery.chargePercent = 63
        snapshot.battery.charge = 5477
        snapshot.battery.currentCapacity = 8694
        snapshot.battery.designCapacity = 8790
        snapshot.battery.cycleCount = 39

        snapshot.network.today = 2_290_000_000
        snapshot.network.yesterday = 3_170_000_000
        snapshot.network.last7Days = 29_790_000_000
        snapshot.network.last30Days = 168_310_000_000
        snapshot.network.dailyTotals = (0..<30).map { _ in UInt64.random(in: 1_000_000_000...6_000_000_000) }

        snapshot.device.uptime = 74 * 3600
        return snapshot
    }
}
