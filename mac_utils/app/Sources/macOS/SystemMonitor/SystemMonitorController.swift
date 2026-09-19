import AppKit
import Darwin
import GlassDoKit

/// Tek bir çalışan uygulamanın anlık bellek kullanımı — listede bir satır.
struct RunningAppUsage: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let icon: NSImage?
    let memoryBytes: UInt64
    /// Sonlandırılması oturumu bozacak süreçlerde `false` — kapatma düğmesi
    /// hiç çizilmiyor. Bkz. `SystemMonitorController.protectedProcessNames`.
    var isTerminable = true

    static func == (lhs: RunningAppUsage, rhs: RunningAppUsage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Makinenin tamamına ait bellek tablosu — Etkinlik İzleyicisi'nin
/// "Bellek" sekmesindeki değerlerle aynı hesap.
struct SystemMemoryStats: Equatable, Sendable {
    /// Takılı toplam fiziksel RAM.
    var total: UInt64 = 0
    /// Uygulamaların ayırdığı, geri alınamayan sayfalar.
    var appMemory: UInt64 = 0
    /// Diske taşınamayan çekirdek/sürücü belleği.
    var wired: UInt64 = 0
    /// Sıkıştırılarak yerden kazanılmış sayfalar.
    var compressed: UInt64 = 0
    /// Dosya önbelleği — gerektiğinde anında serbest bırakılabilir, bu
    /// yüzden "kullanılan" sayılmaz.
    var cached: UInt64 = 0
    var free: UInt64 = 0

    /// Etkinlik İzleyicisi'ndeki "Kullanılan Bellek" ile aynı tanım:
    /// önbellek buraya DAHİL DEĞİL, çünkü baskı altında hemen boşaltılıyor.
    var used: UInt64 { appMemory + wired + compressed }

    var usedFraction: Double {
        total == 0 ? 0 : min(Double(used) / Double(total), 1)
    }
}

/// Dock'ta görünen (normal) uygulamaları bellek kullanımına göre sıralı
/// listeler, makinenin geneline ait bellek tablosunu çıkarır ve kullanıcının
/// seçtiği uygulamayı kapatmasına izin verir.
@MainActor
@Observable
final class SystemMonitorController {
    /// Tek örnek paylaşılıyor: aynı bellek tablosunu hem kenar panelindeki
    /// RAM görünümü hem ana penceredeki sayfa okuyor. İki ayrı denetleyici
    /// aynı süreç listesini iki kez tarar, iki ayrı döngü uyandırırdı.
    static let shared = SystemMonitorController()

    private(set) var apps: [RunningAppUsage] = []
    /// Dock'ta görünmeyen her şey: tarayıcı/editör yardımcı süreçleri
    /// (renderer'lar), arka plan servisleri, çalışma zamanları (java, dart),
    /// çekirdek servisleri. "macOS ve Sistem" dilimini oluşturan yığın
    /// aslında bunlar; liste olmadan o bölüm tek bir kocaman sayıdan
    /// ibaretti ve belleği neyin yediği görünmüyordu.
    private(set) var systemProcesses: [RunningAppUsage] = []
    private(set) var memory = SystemMemoryStats()

    private var refreshTask: _Concurrency.Task<Void, Never>?
    private var subscribers = 0

    private static let refreshInterval: Duration = .seconds(2)

    /// Listelenen kullanıcı uygulamalarının toplamı.
    var appsTotal: UInt64 {
        apps.reduce(into: UInt64(0)) { $0 += $1.memoryBytes }
    }

    /// macOS'in kendisi: kullanılan bellekten listelenen uygulamaların payı
    /// düşülünce geriye kalan her şey — çekirdek, arka plan servisleri,
    /// pencere sunucusu, Spotlight ve Dock'ta görünmeyen süreçler.
    var systemTotal: UInt64 {
        let apps = appsTotal
        return memory.used > apps ? memory.used - apps : 0
    }

    /// Listenin en büyük değeri — satırlardaki oran çubuğunu ölçeklemek için.
    var largestAppMemory: UInt64 {
        apps.first?.memoryBytes ?? 0
    }

    var largestSystemProcessMemory: UInt64 {
        systemProcesses.first?.memoryBytes ?? 0
    }

    /// Bir tüketici abone olur; ilk abone döngüyü başlatır.
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

    /// Son abone bırakınca döngü duruyor.
    func stop() {
        subscribers = max(subscribers - 1, 0)
        guard subscribers == 0 else { return }
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let regularApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && app.processIdentifier != ownPID
        }

        apps = regularApps
            .map { app in
                RunningAppUsage(
                    id: app.processIdentifier,
                    name: app.localizedName ?? L10n.s("Bilinmeyen", "Unknown", "Неизвестно"),
                    icon: app.icon,
                    memoryBytes: Self.physicalFootprint(pid: app.processIdentifier) ?? 0
                )
            }
            .sorted { $0.memoryBytes > $1.memoryBytes }

        // Ölçülemeyen süreçler listeye alınmıyor: root'a ait daemon'ların
        // `proc_pid_rusage` çağrısı izin hatası veriyor ve bunları 0 bayt
        // diye göstermek "hiç bellek kullanmıyor" demek olurdu.
        let appPIDs = Set(regularApps.map(\.processIdentifier))
        systemProcesses = Self.allProcessIDs()
            .filter { $0 != ownPID && !appPIDs.contains($0) }
            .compactMap { pid in
                guard let bytes = Self.physicalFootprint(pid: pid), bytes > 0 else { return nil }
                let name = Self.processName(pid)
                return RunningAppUsage(
                    id: pid, name: name, icon: nil, memoryBytes: bytes,
                    isTerminable: !Self.protectedProcessNames.contains(name)
                )
            }
            .sorted { $0.memoryBytes > $1.memoryBytes }

        memory = Self.systemMemory()
    }

    /// Kullanıcı bir satırdaki kapatma düğmesine bastığında çağrılır.
    /// Yeniden çekmeyi beklemeden satırı hemen listeden düşürür — kapatma
    /// isteği gönderildiği an geri bildirim istenmeyen bir gecikme olmasın.
    func quit(_ app: RunningAppUsage) {
        NSRunningApplication(processIdentifier: app.id)?.terminate()
        apps.removeAll { $0.id == app.id }
    }

    /// Korunan süreç isimleri artık `ProcessSafety`de: aynı kural ağ
    /// panelinin süreç listesinde de geçerli ve iki kopya zamanla
    /// birbirinden ayrışırdı.
    private static var protectedProcessNames: Set<String> { ProcessSafety.protectedNames }

    /// Uygulama olmayan bir süreci sonlandırır.
    ///
    /// `NSRunningApplication` yalnızca Dock uygulamalarını tanıyor; yardımcı
    /// süreçler ve çalışma zamanları (java, dart gibi) için tek yol doğrudan
    /// sinyal göndermek. `SIGKILL` değil `SIGTERM` gönderiliyor: süreç kendi
    /// temizliğini yapıp çıkabilsin — açık dosyaları olan bir çalışma
    /// zamanını sertçe öldürmek veri kaybettirebilir.
    func terminate(_ process: RunningAppUsage) {
        guard process.isTerminable else { return }
        kill(process.id, SIGTERM)
        systemProcesses.removeAll { $0.id == process.id }
    }

    // MARK: - Ölçüm

    /// Etkinlik İzleyicisi'nin "Bellek" sütunuyla aynı ölçüm —
    /// `ri_resident_size` (klasik RSS) yerine `ri_phys_footprint` kullanılır
    /// çünkü paylaşılan sayfaları tekrar saymaz, gerçek kullanıma daha yakın.
    /// `nil` = ölçülemedi (çağıranın o sürece erişim izni yok). Sıfır bayt
    /// ile karıştırılmaması gerekiyor; bkz. `refresh`.
    private static func physicalFootprint(pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result: Int32 = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    /// Makinedeki bütün süreçlerin kimlikleri. İlk çağrı yalnızca sayıyı
    /// sorup arabelleği ona göre ayırıyor; süreç sayısı iki çağrı arasında
    /// artabileceği için pay bırakılıyor.
    private static func allProcessIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var buffer = [pid_t](repeating: 0, count: Int(count) * 2)
        let written = proc_listallpids(
            &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size)
        )
        guard written > 0 else { return [] }
        return Array(buffer.prefix(Int(written))).filter { $0 > 0 }
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }

    /// Çekirdeğin sanal bellek sayaçları (`host_statistics64`) sayfa cinsinden
    /// veriliyor; bayta çevirip Etkinlik İzleyicisi'nin gruplarına ayırıyoruz.
    private static func systemMemory() -> SystemMemoryStats {
        var stats = SystemMemoryStats()
        stats.total = ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return stats }

        // `vm_kernel_page_size` global bir `var` olarak içe aktarıldığı için
        // Swift 6'nın katı eşzamanlılık denetiminden geçmiyor; aynı değeri
        // veren çekirdek sorgusu kullanılıyor.
        var rawPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &rawPageSize) == KERN_SUCCESS else { return stats }
        let pageSize = UInt64(rawPageSize)
        let purgeable = UInt64(vmStats.purgeable_count) * pageSize
        let internalPages = UInt64(vmStats.internal_page_count) * pageSize

        // Geri alınabilir (purgeable) sayfalar "uygulama belleği" sayılmıyor;
        // baskı altında sistem onları uygulamayı kapatmadan boşaltabiliyor.
        stats.appMemory = internalPages > purgeable ? internalPages - purgeable : 0
        stats.wired = UInt64(vmStats.wire_count) * pageSize
        stats.compressed = UInt64(vmStats.compressor_page_count) * pageSize
        stats.cached = UInt64(vmStats.external_page_count) * pageSize + purgeable
        stats.free = UInt64(vmStats.free_count) * pageSize

        return stats
    }
}
