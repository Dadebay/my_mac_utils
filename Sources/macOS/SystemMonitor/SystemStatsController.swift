import Foundation
import WidgetKit
import GlassDoKit

/// İşlemci, bellek, disk, batarya ve ağ sayaçlarını tek bir zamanlayıcıdan
/// besler. Beş ayrı izleyici yerine tek döngü kullanılıyor — hepsi aynı
/// anda görünüyor, ayrı ayrı uyandırmanın enerji maliyeti gereksiz olurdu.
///
/// Ölçümün kendisi `SystemSampler`'da; burada yalnızca zamanlama, grafik
/// geçmişi ve widget'a bırakılan anlık görüntü var.
///
/// Tek örnek paylaşılıyor (`shared`) çünkü artık üç ayrı tüketici var:
/// sistem panosu, menü çubuğu ölçerleri ve widget anlık görüntüsü. Üçü ayrı
/// denetleyici kullansaydı aynı sayaçlar üç kez okunur, geçmişleri de
/// birbirinden kayardı. `start()` / `stop()` sayaçlı: son tüketici de
/// bırakınca döngü duruyor.
@MainActor
@Observable
final class SystemStatsController {
    static let shared = SystemStatsController()

    private(set) var cpu = CPULoadStats()
    private(set) var memory = MemoryStats()
    private(set) var disk = DiskStats()
    private(set) var battery = BatteryStats()
    private(set) var network = NetworkStats()
    private(set) var device = DeviceStats()

    private var refreshTask: _Concurrency.Task<Void, Never>?
    private var subscribers = 0

    /// Bellek paneliyle aynı ritim — iki saniye, göz yormadan güncel.
    private static let refreshInterval: Duration = .seconds(2)
    /// Grafiklerde tutulan örnek sayısı.
    private static let historyLength = 46
    /// Disk kapasitesi saniyede bir değişmez; her N örnekte bir okunur.
    private static let diskRefreshEvery = 15
    /// Sıcaklık sensörü taraması 70'in üzerinde servis dolaşıyor; her
    /// turda değil, iki turda bir okunuyor.
    private static let temperatureRefreshEvery = 2
    /// Widget'ın okuduğu dosyaya bu sıklıkta yazılıyor. Her iki saniyede
    /// bir diske yazmanın karşılığı yok: widget zaten en iyi ihtimalle
    /// dakikada bir yenileniyor.
    private static let snapshotInterval: TimeInterval = 15
    /// WidgetKit'in yenileme bütçesi günlük ve sınırlı; bundan sık
    /// dürtmek bütçeyi tüketmekten başka bir şey yapmaz.
    private static let widgetReloadInterval: TimeInterval = 5 * 60

    /// Geçmiş uygulama ömrü boyunca ayrıca toplanıyor; buradaki görünüm
    /// yalnızca güncel toplamları okur.
    private let history = NetworkHistoryStore.shared

    private var previousCPUTicks: SystemSampler.CPUTicks?
    private var previousNetworkSample: (bytes: (received: UInt64, sent: UInt64), at: Date)?
    private var tick = 0
    private var lastSnapshotWrite = Date.distantPast
    private var lastWidgetReload = Date.distantPast

    /// Bir tüketici ölçüme abone olur. İlk abone döngüyü başlatır.
    func start() {
        subscribers += 1
        guard refreshTask == nil else { return }

        refresh()
        refreshTask = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(for: Self.refreshInterval)
                guard !_Concurrency.Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    /// Abonelik biter; son abone de gidince döngü durur.
    func stop() {
        subscribers = max(subscribers - 1, 0)
        guard subscribers == 0 else { return }

        refreshTask?.cancel()
        refreshTask = nil
        history.flush()
    }

    private func refresh() {
        refreshCPU()
        refreshMemory()
        refreshNetwork()
        refreshBattery()
        device = SystemSampler.deviceStats()

        // Disk yavaş değişen bir büyüklük ve sorgusu dosya sistemine gidiyor;
        // her turda okumak boşuna maliyet.
        if tick % Self.diskRefreshEvery == 0 {
            refreshDisk()
        }
        tick &+= 1

        publishSnapshotIfNeeded()
    }

    /// Bir seriyi sabit uzunlukta tutar.
    private static func appending<T>(_ value: T, to series: [T]) -> [T] {
        var next = series
        next.append(value)
        if next.count > historyLength {
            next.removeFirst(next.count - historyLength)
        }
        return next
    }

    // MARK: - İşlemci

    private func refreshCPU() {
        var next = cpu
        next.coreCount = ProcessInfo.processInfo.processorCount
        next.thermalPressure = SystemSampler.thermalPressure()

        if tick % Self.temperatureRefreshEvery == 0 {
            next.temperature = CPUTemperature.current()
        }
        if let temperature = next.temperature {
            next.temperatureHistory = Self.appending(temperature, to: next.temperatureHistory)
        }

        guard let ticks = SystemSampler.cpuTicks() else {
            cpu = next
            return
        }
        defer { previousCPUTicks = ticks }

        // İlk turda önceki sayaç yok; fark alınamadığı için bütün çekirdekler
        // sıfır dönüyor. Grafik yine de boş sütunlarla açılsın — hiç
        // açılmamış gibi görünmesin.
        next.perCoreUsage = SystemSampler.perCoreUsage(
            from: previousCPUTicks?.cores ?? [],
            to: ticks.cores
        )
        // Çekirdek sayısı ölçümün kendisinden geliyor: `processorCount` ile
        // sütun sayısının ayrışması grafiği yalancı yapardı.
        if !next.perCoreUsage.isEmpty {
            next.coreCount = next.perCoreUsage.count
        }

        guard let previous = previousCPUTicks,
              let usage = SystemSampler.cpuUsage(from: previous, to: ticks)
        else {
            cpu = next
            return
        }

        next.userUsage = usage.user
        next.systemUsage = usage.system
        next.usage = min(usage.user + usage.system, 1)
        next.history = Self.appending(next.usage, to: next.history)
        next.layeredHistory = Self.appending([usage.user, usage.system], to: next.layeredHistory)

        cpu = next
    }

    // MARK: - Bellek

    private func refreshMemory() {
        var next = SystemSampler.memoryStats()
        next.history = Self.appending(
            [
                Double(next.active) / Double(max(next.total, 1)),
                Double(next.wired) / Double(max(next.total, 1)),
                Double(next.compressed) / Double(max(next.total, 1)),
            ],
            to: memory.history
        )
        memory = next
    }

    // MARK: - Disk

    private func refreshDisk() {
        var next = SystemSampler.diskStats()
        next.history = Self.appending(next.usedFraction, to: disk.history)
        disk = next
    }

    // MARK: - Batarya

    private func refreshBattery() {
        var next = SystemSampler.batteryStats()
        next.healthHistory = Self.appending(next.healthFraction, to: battery.healthHistory)
        battery = next
    }

    // MARK: - Ağ

    private func refreshNetwork() {
        let sample = NetworkInterfaceCounters.current()
        let now = Date()

        var next = network
        next.totalReceived = sample.received
        next.totalSent = sample.sent

        if let previous = previousNetworkSample {
            let elapsed = now.timeIntervalSince(previous.at)
            if elapsed > 0 {
                let down = sample.received >= previous.bytes.received
                    ? sample.received - previous.bytes.received
                    : 0
                let up = sample.sent >= previous.bytes.sent
                    ? sample.sent - previous.bytes.sent
                    : 0
                next.downloadRate = Double(down) / elapsed
                next.uploadRate = Double(up) / elapsed
            }
        }
        previousNetworkSample = (bytes: (sample.received, sample.sent), at: now)

        next.downloadHistory = Self.appending(next.downloadRate, to: next.downloadHistory)
        next.uploadHistory = Self.appending(next.uploadRate, to: next.uploadHistory)

        // Aynı örneği geçmişe de işle: panel açıkken iki saniyelik çözünürlük,
        // kapalıyken paylaşılan toplayıcının beş saniyeliği geçerli.
        history.recordCurrentTraffic()
        let windows = history.windowTotals
        next.today = windows.today
        next.yesterday = windows.yesterday
        next.last7Days = windows.last7
        next.last30Days = windows.last30
        next.dailyTotals = history.dailyTotals(days: 30)

        let interface = NetworkInterfaceCounters.primaryInterface()
        next.interfaceName = interface.name
        next.localAddress = interface.address
        next.isVPNActive = NetworkInterfaceCounters.isVPNActive()

        network = next
    }

    // MARK: - Widget'a bırakılan anlık görüntü

    private func publishSnapshotIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastSnapshotWrite) >= Self.snapshotInterval else { return }
        lastSnapshotWrite = now

        let snapshot = SystemSnapshot(
            date: now,
            cpu: cpu,
            memory: memory,
            disk: disk,
            battery: battery,
            network: network,
            device: device,
            language: L10n.language.rawValue
        )

        // Diske yazma ölçüm döngüsünü bekletmesin.
        _Concurrency.Task.detached(priority: .utility) {
            SystemSnapshotStore.write(snapshot)
        }

        guard now.timeIntervalSince(lastWidgetReload) >= Self.widgetReloadInterval else { return }
        lastWidgetReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }
}
