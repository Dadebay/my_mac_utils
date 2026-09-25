import AppKit
import Darwin
import GlassDoKit

/// Tek bir sürecin anlık işlemci kullanımı — listede bir satır.
struct CPUProcessUsage: Identifiable, Equatable {
    let id: pid_t
    let name: String
    /// Etkinlik İzleyicisi'nin "% CPU" sütunuyla aynı ölçek: bir çekirdeğin
    /// tamamı %100. Çok çekirdekli bir süreç %100'ü aşabiliyor.
    let percent: Double
}

/// Makinedeki süreçleri işlemci kullanımına göre sıralar.
///
/// İşlemci yüzdesi anlık bir değer değil, iki ölçüm arasındaki farktan
/// çıkıyor: her süreç için harcanan toplam CPU süresi (kullanıcı + sistem)
/// okunuyor, bir sonraki ölçümde aradaki artış geçen duvar saatine
/// bölünüyor. İlk ölçümde karşılaştırılacak bir şey olmadığı için liste
/// ikinci ölçümle doluyor.
///
/// Root'a ait süreçlerin sayaçları okunamıyor (`EPERM`); onlar listede
/// yok. Zaten kullanıcı olarak kapatılamazlar.
@MainActor
@Observable
final class CPUProcessMonitor {
    static let shared = CPUProcessMonitor()

    private(set) var processes: [CPUProcessUsage] = []
    private(set) var hasSampled = false

    /// Panel dar: en yoğun birkaç süreç yeterli, uzun kuyruk gürültü.
    private static let limit = 8
    /// %0.5'in altı "boşta" — listeyi kıpır kıpır oynatmasın.
    private static let floor = 0.5
    private static let interval: Duration = .seconds(2)

    private var previous: [pid_t: UInt64] = [:]
    private var previousTime: UInt64 = 0
    private var task: _Concurrency.Task<Void, Never>?
    private var subscribers = 0

    func start() {
        subscribers += 1
        guard task == nil else { return }
        sample()
        task = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(for: Self.interval)
                guard !_Concurrency.Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    func stop() {
        subscribers = max(subscribers - 1, 0)
        guard subscribers == 0 else { return }
        task?.cancel()
        task = nil
        // Bir sonraki açılışta eski sayaçlarla kıyaslanmasın: aradaki uzun
        // boşluk bütün yüzdeleri yapay olarak küçültürdü.
        previous = [:]
        previousTime = 0
    }

    /// Kapatıldıktan sonra satır bir sonraki ölçümü beklemeden düşüyor.
    func remove(_ pid: pid_t) {
        processes.removeAll { $0.id == pid }
    }

    private func sample() {
        let now = mach_absolute_time()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var current: [pid_t: UInt64] = [:]

        for pid in Self.allProcessIDs() where pid != ownPID {
            if let time = Self.cpuTime(pid: pid) { current[pid] = time }
        }

        defer {
            previous = current
            previousTime = now
        }

        guard previousTime > 0, now > previousTime else { return }
        let wall = Double(now - previousTime)

        processes = current
            .compactMap { pid, time -> CPUProcessUsage? in
                guard let before = previous[pid], time >= before else { return nil }
                let percent = Double(time - before) / wall * 100
                guard percent >= Self.floor else { return nil }
                return CPUProcessUsage(id: pid, name: Self.displayName(pid), percent: percent)
            }
            .sorted { $0.percent > $1.percent }
            .prefix(Self.limit)
            .map { $0 }
        hasSampled = true
    }

    /// Sandbox'ta da çalışan yol için bkz. `ProcessMetrics`.
    private static func cpuTime(pid: pid_t) -> UInt64? {
        ProcessMetrics.cpuTime(pid: pid)
    }

    /// Varsa uygulamanın kendi adı (`proc_name`'in 16 karakterde kestiği
    /// ad yerine), yoksa süreç adı.
    private static func displayName(_ pid: pid_t) -> String {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }

    private static func allProcessIDs() -> [pid_t] {
        ProcessMetrics.allProcessIDs()
    }
}
