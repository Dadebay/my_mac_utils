import Foundation
import Darwin

/// Hangi işlemin işlemciyi yediğini bulur.
///
/// `libproc`'un `proc_pid_rusage`'ı her işlemin biriktirdiği CPU süresini
/// veriyor; iki örnek arasındaki fark, aradaki gerçek süreye bölününce
/// yüzdeyi çıkarıyor. `ps` çalıştırmak daha kısa olurdu ama sandbox alt
/// süreç açmaya izin vermiyor — Release yapısında hiç çalışmazdı.
///
/// **Birim tuzağı:** `ri_user_time`/`ri_system_time` nanosaniye değil,
/// mach zaman birimi. Apple Silicon'da timebase 125/3, yani ham farkı
/// olduğu gibi saniyeye çevirmek gerçek yükün 1/41'ini gösteriyor
/// (ölçüldü: %100 CPU yiyen bir işlem %2,4 görünüyordu). `scale` bu
/// yüzden var.
///
/// **Göremediği:** root'a ait işlemler. `proc_pid_rusage` başka kullanıcının
/// işlemi için `EPERM` dönüyor (bu Mac'te 138 işlemin ~30'u). Kullanıcının
/// kendi çalıştırdığı şeyler — `ollama` dahil — görünüyor; asıl suçlu bir
/// sistem servisiyse liste onu atlar, o yüzden çağıran taraf "bulunamadı"
/// durumunu da ele almak zorunda.
enum TopProcessSampler {
    struct Sample: Sendable {
        var pid: Int32
        var name: String
        /// Tek çekirdeğin tamamı = 100. Çok çekirdekli bir işlem 100'ün
        /// üstüne çıkar (`ollama` 15 çekirdekli bir Mac'te %1400'e kadar) —
        /// Activity Monitor da aynı ölçeği kullanıyor.
        var cpuPercent: Double
    }

    /// İşlem listesi bu yapıda okunabiliyor mu.
    ///
    /// **Ölçüldü:** App Sandbox açıkken `proc_listallpids` sıfır işlem
    /// dönüyor (sandbox'lı bir `.app` paketiyle sınandı) — yani Mac App
    /// Store yapısında suçlu işlem adı hiç bulunamıyor. Sandbox'sız
    /// yapıda (Debug ve doğrudan dağıtım) 139 işlemin ~109'u okunuyor,
    /// kalanı root'a ait.
    ///
    /// Çağıran taraf buna bakıp bildirim metnini ona göre kuruyor:
    /// "baskın işlem bulunamadı" ile "bu yapıda işlemler görünmüyor"
    /// farklı iki şey, ikisini aynı cümleyle geçmek kullanıcıyı yanıltır.
    static var canEnumerate: Bool {
        proc_listallpids(nil, 0) > 0
    }

    /// İki örnek arasındaki toplam CPU süresi. Anlık değil: `interval`
    /// kadar bekleniyor, çünkü tek bir okuma yalnızca "bu işlem doğduğundan
    /// beri ne kadar CPU yedi" der — şu an yiyip yemediğini söylemez.
    static func topProcesses(
        interval: Duration = .seconds(2),
        limit: Int = 3
    ) async -> [Sample] {
        let before = snapshot()
        guard !before.isEmpty else { return [] }

        let started = ContinuousClock.now
        try? await _Concurrency.Task.sleep(for: interval)
        let elapsed = (ContinuousClock.now - started).seconds
        guard elapsed > 0 else { return [] }

        let after = snapshot()
        var samples: [Sample] = []
        for (pid, end) in after {
            guard let start = before[pid], end > start else { continue }
            let seconds = Double(end - start) * scale / 1_000_000_000
            let percent = seconds / elapsed * 100
            // %5 altı gürültü: onlarca yardımcı süreç sürekli %1-2
            // dolaşıyor, bildirimde adı geçmesinin bir anlamı yok.
            guard percent >= 5 else { continue }
            samples.append(Sample(pid: pid, name: name(of: pid), cpuPercent: percent))
        }
        return samples.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit).map { $0 }
    }

    // MARK: - Çekirdek

    private static let scale: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom != 0 else { return 1 }
        return Double(info.numer) / Double(info.denom)
    }()

    private static func snapshot() -> [Int32: UInt64] {
        var result: [Int32: UInt64] = [:]
        for pid in allPIDs() {
            if let time = cpuTime(of: pid) { result[pid] = time }
        }
        return result
    }

    private static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Sayı ile dizinin doldurulması arasında yeni işlem doğabilir;
        // fazladan pay bırakılıyor ki taşan kısım sessizce kesilmesin.
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let byteCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard byteCount > 0 else { return [] }
        return Array(pids.prefix(Int(byteCount) / MemoryLayout<Int32>.size)).filter { $0 > 0 }
    }

    private static func cpuTime(of pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard status == 0 else { return nil }
        return info.ri_user_time &+ info.ri_system_time
    }

    private static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, 255)
        guard length > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
