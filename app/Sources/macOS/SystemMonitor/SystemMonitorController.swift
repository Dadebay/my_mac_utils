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
    /// Bellek tablosunun sahibi `SystemSampler`. Burada ikinci bir hesap
    /// tutulmuyordu; tutuluyordu ve iki panel aynı anda farklı yüzde
    /// gösteriyordu (bkz. plans/014).
    private(set) var memory = MemoryStats()

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

        memory = SystemSampler.memoryStats()
    }

    /// Kullanıcı bir satırdaki kapatma düğmesine bastığında çağrılır.
    /// Yeniden çekmeyi beklemeden satırı hemen listeden düşürür — kapatma
    /// isteği gönderildiği an geri bildirim istenmeyen bir gecikme olmasın.
    /// Eylemin sonucu. Başarısızlık sessiz kalmamalı: liste satırını
    /// silip "oldu" gibi davranmak, süreç hâlâ ayaktayken kullanıcıyı
    /// yanıltıyordu.
    private(set) var actionMessage: String?

    func dismissActionMessage() {
        actionMessage = nil
    }

    func quit(_ app: RunningAppUsage) {
        actionMessage = nil
        // java, dart gibi çalışma zamanları Dock uygulaması değil:
        // `NSRunningApplication` onlar için `nil` dönüyor ve panel "sinyal
        // gönderilemedi" diyordu, oysa süreç kullanıcınındı ve kapatılabilirdi.
        // Onlar doğrudan sinyal yolundan gidiyor.
        guard let running = NSRunningApplication(processIdentifier: app.id) else {
            terminate(app)
            return
        }
        guard running.terminate() else {
            actionMessage = L10n.processQuitDenied(app.name)
            return
        }
        apps.removeAll { $0.id == app.id }
        verifyGone(app)
    }

    /// Sinyalden sonra sürecin gerçekten gittiğini doğruluyor. Çoğu yardımcı
    /// süreç (tarayıcı işleyicileri, `mediaanalysisd` gibi launchd
    /// servisleri) kapanır kapanmaz yeniden doğuyor; kullanıcı "hiçbir şey
    /// olmadı" diye görüyordu, oysa olan şuydu.
    private func verifyGone(_ process: RunningAppUsage) {
        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .milliseconds(700))
            guard kill(process.id, 0) == 0 else { return }
            actionMessage = L10n.processQuitRestarted(process.name)
        }
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
        actionMessage = nil
        guard process.isTerminable else {
            actionMessage = L10n.processQuitDenied(process.name)
            return
        }

        guard kill(process.id, SIGTERM) == 0 else {
            // EPERM: sürecin sahibi başka bir kullanıcı (çoğu kez root) ya
            // da sistem bütünlüğü koruması engelliyor.
            actionMessage = L10n.processQuitDenied(process.name)
            return
        }

        systemProcesses.removeAll { $0.id == process.id }
        verifyGone(process)
    }

    // MARK: - Ölçüm

    /// `nil` = ölçülemedi (çağıranın o sürece erişim izni yok). Sıfır bayt
    /// ile karıştırılmaması gerekiyor; bkz. `refresh` ve `ProcessMetrics`.
    private static func physicalFootprint(pid: pid_t) -> UInt64? {
        ProcessMetrics.memory(pid: pid)
    }

    /// Makinedeki bütün süreçlerin kimlikleri — sandbox'ta da (bkz.
    /// `ProcessMetrics`).
    private static func allProcessIDs() -> [pid_t] {
        ProcessMetrics.allProcessIDs()
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }

}
