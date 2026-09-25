import Darwin

/// Başka bir sürecin bellek ve işlemci sayaçlarını okur.
///
/// İki kaynak var ve sandbox ikisine farklı davranıyor:
///
/// - `proc_pid_rusage`: Etkinlik İzleyicisi'nin "Bellek" sütunuyla aynı
///   `ri_phys_footprint`'i veriyor — paylaşılan sayfaları tekrar saymadığı
///   için gerçeğe en yakın ölçü. **Ama App Sandbox'ta başka süreçler için
///   `EPERM` dönüyor.** Mağaza (Release) sürümü sandbox'ta olduğu için
///   bellek listesinde her uygulama "0 bayt", işlemci listesi de boş
///   görünüyordu; Debug sandbox'sız olduğu için sorun orada yoktu.
/// - `proc_pidinfo(PROC_PIDTASKINFO)`: sandbox'ta da çalışıyor (ölçüldü).
///   Bellek olarak klasik RSS'i veriyor — paylaşılan sayfaları da saydığı
///   için footprint'ten biraz yüksek, ama sıfırdan çok daha doğru.
///
/// Önce hassas yol deneniyor, izin yoksa ikincisine düşülüyor.
///
/// Süreç listesinde de aynı durum: `proc_listallpids` sandbox'ta hiç süreç
/// döndürmüyor (sistem süreçleri listesi boş kalıyordu), `sysctl`
/// `KERN_PROC_ALL` ise döndürüyor.
enum ProcessMetrics {

    /// Makinedeki bütün süreçlerin kimlikleri.
    static func allProcessIDs() -> [pid_t] {
        let listed = listAllPIDs()
        return listed.isEmpty ? sysctlPIDs() : listed
    }

    private static func listAllPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Sayı ile dizinin doldurulması arasında yeni süreç doğabilir; pay
        // bırakılıyor ki taşan kısım sessizce kesilmesin.
        var buffer = [pid_t](repeating: 0, count: Int(count) * 2)
        let written = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard written > 0 else { return [] }
        return Array(buffer.prefix(Int(written))).filter { $0 > 0 }
    }

    private static func sysctlPIDs() -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        size += size / 8
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        let result = procs.withUnsafeMutableBytes {
            sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return [] }
        return procs.prefix(size / stride).map(\.kp_proc.p_pid).filter { $0 > 0 }
    }

    /// Sürecin kullandığı bellek. `nil` = hiçbir yoldan okunamadı
    /// (çoğunlukla root'a ait süreçler) — sıfır bayttan ayrı tutulmalı.
    static func memory(pid: pid_t) -> UInt64? {
        if let usage = rusage(pid: pid) { return usage.ri_phys_footprint }
        return taskInfo(pid: pid).map { $0.pti_resident_size }
    }

    /// Sürecin şimdiye kadar harcadığı toplam CPU süresi (kullanıcı +
    /// sistem). İki kaynak da aynı birimde: başlık dosyası "nanosaniye"
    /// dese de Apple Silicon'da mach tick (ölçüldü: 1 sn yoğun iş ≈ 24
    /// milyon, iki kaynakta da aynı). `mach_absolute_time` ile aynı birim.
    static func cpuTime(pid: pid_t) -> UInt64? {
        if let usage = rusage(pid: pid) { return usage.ri_user_time &+ usage.ri_system_time }
        return taskInfo(pid: pid).map { $0.pti_total_user &+ $0.pti_total_system }
    }

    private static func rusage(pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result: Int32 = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info : nil
    }

    private static func taskInfo(pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size ? info : nil
    }
}
