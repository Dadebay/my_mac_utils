import Darwin
import Foundation
import IOKit

/// Çekirdekten tek seferlik ölçüm alan saf işlevler.
///
/// Geçmiş biriktirme ve zamanlama burada değil: aynı okumaları hem
/// uygulamadaki `SystemStatsController` (iki saniyede bir, grafik geçmişiyle)
/// hem de widget uzantısı (zaman çizelgesi başına bir kez, geçmişsiz)
/// kullanıyor. İki süreçte iki ayrı kopya olsaydı zamanla birbirinden
/// kayarlardı.
enum SystemSampler {

    // MARK: - İşlemci

    /// Tüm çekirdeklerin biriken tik sayaçları. Yük, iki örnek arasındaki
    /// farktan hesaplanır — tek başına bir örnek yük bilgisi taşımaz.
    struct CPUTicks: Equatable, Sendable {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        /// Aynı örneğin çekirdek başına dökümü, mantıksal çekirdek sırasında.
        var cores: [CoreTicks] = []

        var total: UInt64 { user &+ system &+ idle }
    }

    /// Tek bir mantıksal çekirdeğin biriken tik sayaçları.
    ///
    /// `nice` burada ayrı duruyor: toplamda kullanıcı payına katılıyor ama
    /// çekirdek başına hesapta sayaçların tek tek farkı alınıyor — biri
    /// geri sararsa yalnızca o pay sıfırlansın, diğerleri bozulmasın.
    struct CoreTicks: Equatable, Sendable {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var nice: UInt64 = 0
        var idle: UInt64 = 0
    }

    /// `host_processor_info` çekirdekten ayrılmış bir tampon döndürür;
    /// sızmaması için elle serbest bırakılıyor.
    static func cpuTicks() -> CPUTicks? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        var ticks = CPUTicks()
        ticks.cores.reserveCapacity(Int(cpuCount))
        let states = Int(CPU_STATE_MAX)

        for core in 0..<Int(cpuCount) {
            let base = core * states

            let coreTicks = CoreTicks(
                user: UInt64(max(info[base + Int(CPU_STATE_USER)], 0)),
                system: UInt64(max(info[base + Int(CPU_STATE_SYSTEM)], 0)),
                nice: UInt64(max(info[base + Int(CPU_STATE_NICE)], 0)),
                idle: UInt64(max(info[base + Int(CPU_STATE_IDLE)], 0))
            )
            ticks.cores.append(coreTicks)

            // Toplamda `nice` de kullanıcı alanı sayılır — ayrı bir kategori
            // olarak göstermek kimseye bir şey anlatmıyor.
            ticks.user &+= coreTicks.user &+ coreTicks.nice
            ticks.system &+= coreTicks.system
            ticks.idle &+= coreTicks.idle
        }

        return ticks
    }

    /// İki tik örneğinden kullanıcı ve sistem paylarını çıkarır.
    /// Sayaçlar monoton artar; yine de negatife düşmeye karşı korunuyor.
    static func cpuUsage(from previous: CPUTicks, to current: CPUTicks) -> (user: Double, system: Double)? {
        let userDelta = current.user >= previous.user ? current.user - previous.user : 0
        let systemDelta = current.system >= previous.system ? current.system - previous.system : 0
        let totalDelta = current.total >= previous.total ? current.total - previous.total : 0
        guard totalDelta > 0 else { return nil }
        return (Double(userDelta) / Double(totalDelta), Double(systemDelta) / Double(totalDelta))
    }

    /// İki örnek arasındaki çekirdek başına yük, 0…1, mantıksal çekirdek
    /// sırasında.
    ///
    /// Saf işlev: çekirdeğe hiç dokunmuyor, yalnızca iki sayaç dizisini
    /// karşılaştırıyor — hesabın kendisi böylece test edilebiliyor.
    /// Önceki örnek yoksa (ilk tur) fark alınamaz; o durumda bütün
    /// çekirdekler 0 döner, çünkü tek bir örnek yük bilgisi taşımaz.
    static func perCoreUsage(from previous: [CoreTicks], to current: [CoreTicks]) -> [Double] {
        current.enumerated().map { index, core in
            guard index < previous.count else { return 0 }
            return coreUsage(from: previous[index], to: core)
        }
    }

    /// Tek çekirdeğin iki örnek arasındaki yükü, 0…1.
    static func coreUsage(from previous: CoreTicks, to current: CoreTicks) -> Double {
        let userDelta = delta(from: previous.user, to: current.user)
        let systemDelta = delta(from: previous.system, to: current.system)
        let niceDelta = delta(from: previous.nice, to: current.nice)
        let idleDelta = delta(from: previous.idle, to: current.idle)

        let activeDelta = userDelta &+ systemDelta &+ niceDelta
        let totalDelta = activeDelta &+ idleDelta
        guard totalDelta > 0 else { return 0 }

        return min(max(Double(activeDelta) / Double(totalDelta), 0), 1)
    }

    /// Sayaçlar monoton artar; yine de geri sarmaya karşı korunuyor.
    /// `UInt64` çıkarması negatife düştüğünde sarıp devasa bir sayı
    /// üretirdi — bir çekirdek anında %100 görünürdü.
    private static func delta(from previous: UInt64, to current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    static func thermalPressure() -> ThermalPressure {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    // MARK: - Bellek

    static func memoryStats() -> MemoryStats {
        var stats = MemoryStats()
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
        let external = UInt64(vmStats.external_page_count) * pageSize

        stats.active = UInt64(vmStats.active_count) * pageSize
        stats.wired = UInt64(vmStats.wire_count) * pageSize
        stats.compressed = UInt64(vmStats.compressor_page_count) * pageSize
        stats.cached = external + purgeable
        stats.free = UInt64(vmStats.free_count) * pageSize

        let swap = swapUsage()
        stats.swapUsed = swap.used
        stats.swapTotal = swap.total

        return stats
    }

    /// `vm.swapusage` sysctl'i takas dosyasının boyutunu ve kullanımını verir.
    private static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    // MARK: - Disk

    /// APFS'te `/` salt okunur sistem birimidir ve daima ~%3 dolu görünür.
    /// Kullanıcının doldurduğu yer veri birimi; ad ise kök birimden okunur
    /// ("Macintosh HD"), çünkü veri birimi "Data" diye adlandırılmıştır.
    static func diskStats() -> DiskStats {
        var stats = DiskStats()

        let dataVolume = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        if let values = try? dataVolume.resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        ),
           let total = values.volumeTotalCapacity,
           let available = values.volumeAvailableCapacity {
            stats.total = UInt64(max(total, 0))
            let free = UInt64(max(available, 0))
            stats.used = stats.total > free ? stats.total - free : 0
        }

        let root = URL(fileURLWithPath: "/", isDirectory: true)
        if let values = try? root.resourceValues(forKeys: [.volumeNameKey]),
           let name = values.volumeName {
            stats.volumeName = name
        }

        return stats
    }

    // MARK: - Batarya

    /// `AppleSmartBattery` IORegistry girdisi. `AppleRawMaxCapacity`
    /// bataryanın bugün tutabildiği şarj, `DesignCapacity` fabrika değeri —
    /// sağlık yüzdesi bu ikisinin oranı.
    static func batteryStats() -> BatteryStats {
        var stats = BatteryStats()

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return stats }
        defer { IOObjectRelease(service) }

        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        }

        func number(_ key: String) -> Int? {
            (property(key) as? NSNumber)?.intValue
        }

        func flag(_ key: String) -> Bool {
            (property(key) as? NSNumber)?.boolValue ?? false
        }

        // Yeni makinelerde ham kapasite `AppleRawMaxCapacity`, bir kısmında
        // yalnızca `NominalChargeCapacity` bulunuyor.
        let maxCapacity = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity")
        guard let maxCapacity, let design = number("DesignCapacity"), design > 0 else {
            return stats
        }

        stats.isPresent = true
        stats.currentCapacity = UInt64(max(maxCapacity, 0))
        stats.designCapacity = UInt64(design)
        stats.cycleCount = number("CycleCount") ?? 0
        stats.hasPermanentFailure = (number("PermanentFailureStatus") ?? 0) != 0

        stats.charge = UInt64(max(number("AppleRawCurrentCapacity") ?? 0, 0))
        stats.chargePercent = number("CurrentCapacity") ?? 0

        // Sıcaklık santigradın yüzde biri cinsinden geliyor (3023 → 30,23 °C).
        if let raw = number("Temperature") {
            stats.temperature = Double(raw) / 100
        }
        // Gerilim milivolt.
        if let raw = number("Voltage") {
            stats.voltage = Double(raw) / 1000
        }
        // Akım miliamper ve İŞARETLİ: deşarjda negatif. IORegistry değeri
        // işaretsiz 64 bit olarak geldiği için negatifler devasa sayılara
        // sarılıyor — `Int64` bit deseni olarak yeniden yorumlanmalı.
        if let raw = property("Amperage") as? NSNumber {
            stats.amperage = Double(Int64(bitPattern: raw.uint64Value)) / 1000
        }

        stats.isAdapterConnected = flag("ExternalConnected")
        stats.isCharging = flag("IsCharging")

        // Sistem hesaplayamadığında 0 ya da 65535 döner; ikisi de anlamsız.
        if let remaining = number("TimeRemaining"), remaining > 0, remaining < 60 * 24 {
            stats.minutesRemaining = remaining
        }

        return stats
    }

    // MARK: - Makine

    static func deviceStats() -> DeviceStats {
        DeviceStats(uptime: ProcessInfo.processInfo.systemUptime)
    }
}

/// Çekirdeğin arayüz bayt sayaçları. Hem uygulama ömrü boyunca çalışan
/// geçmiş toplayıcısı hem de anlık hızı hesaplayan panel görünümü aynı
/// kaynağı okusun diye ortak bir yerde.
extension UInt64 {
    /// Taşmada sarmalamak yerine tavanda kalır.
    ///
    /// Bayt sayaçlarında `&+` kullanmak taşmayı sessizce gizliyordu: bir kez
    /// sarmalayan toplam sıfıra düşüp "bugün" değerini tamamen bozardı.
    /// Doymuş toplama en kötü ihtimalle değeri tavanda dondurur — yanlış ama
    /// fark edilebilir, veri bozucu değil.
    func saturatingAdding(_ other: UInt64) -> UInt64 {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }
}

/// Tek bir ağ arayüzünün açılıştan beri taşıdığı bayt sayacı.
///
/// Toplam yerine arayüz bazında taşınıyor: hangi sayacın sıfırlandığını,
/// hangi arayüzün kaybolduğunu ancak isimle takip edince anlayabiliyoruz
/// (bkz. `NetworkUsageAccumulator`). Tek bir toplam değerde VPN açılıp
/// kapandığında toplamın neden düştüğü ayırt edilemiyordu.
struct NetworkInterfaceSample: Equatable, Sendable {
    let name: String
    let received: UInt64
    let sent: UInt64
    let flags: UInt32
}

/// Hangi arayüzün "gerçek internet trafiği" sayıldığına karar veren saf
/// politika. Saf tutuluyor ki isim listesi görünümlere dağılmasın ve
/// birim testiyle doğrulanabilsin.
enum NetworkInterfacePolicy {
    /// Sanal, tünel ve eşler-arası arayüzler. Bunların baytları ya fiziksel
    /// arayüzde zaten sayılıyor (VPN: `utun` üzerinden geçen her bayt
    /// `en0`'dan da geçer) ya da internet trafiği değil (AirDrop `awdl0`,
    /// köprü `bridge0`).
    static let excludedPrefixes = [
        "lo", "utun", "ipsec", "ppp", "bridge", "awdl",
        "llw", "ap", "p2p", "gif", "stf", "anpi",
    ]

    /// Yalnızca ayakta ve çalışır durumdaki fiziksel Wi-Fi/Ethernet
    /// arayüzleri (`en*`). Adaptör değişimini bozmamak için tek bir isme
    /// (`en0`) sabitlenmiyor: takılan bir USB-Ethernet `en5` olarak gelir ve
    /// kendi deltasıyla sayılmaya devam eder.
    static func isPhysicalDataInterface(name: String, flags: UInt32) -> Bool {
        guard !name.isEmpty else { return false }
        guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_RUNNING) != 0 else { return false }
        guard flags & UInt32(IFF_LOOPBACK) == 0 else { return false }
        guard !excludedPrefixes.contains(where: { name.hasPrefix($0) }) else { return false }
        return name.hasPrefix("en")
    }

    static func physical(in samples: [NetworkInterfaceSample]) -> [NetworkInterfaceSample] {
        samples.filter { isPhysicalDataInterface(name: $0.name, flags: $0.flags) }
    }
}

enum NetworkInterfaceCounters {
    /// Her arayüzün bağlantı katmanı sayacı — filtresiz, ham liste.
    static func allSamples() -> [NetworkInterfaceSample] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }

        var samples: [NetworkInterfaceSample] = []

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            // Yalnızca AF_LINK girdileri sayaç taşır; aynı arayüzün IPv4/IPv6
            // girdileri tekrar sayılmasın diye eleniyor.
            guard pointer.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let data = pointer.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else {
                continue
            }

            samples.append(
                NetworkInterfaceSample(
                    name: String(cString: pointer.pointee.ifa_name),
                    received: UInt64(data.pointee.ifi_ibytes),
                    sent: UInt64(data.pointee.ifi_obytes),
                    flags: pointer.pointee.ifa_flags
                )
            )
        }

        return samples
    }

    /// Günlük toplamın ve anlık hızın ortak kaynağı: yalnızca fiziksel
    /// veri arayüzleri. İkisinin farklı arayüz kümesi ölçmemesi şart —
    /// aksi hâlde panel ile widget farklı "bugün" gösterir.
    static func physicalSamples() -> [NetworkInterfaceSample] {
        NetworkInterfacePolicy.physical(in: allSamples())
    }

    /// Fiziksel arayüzlerin açılıştan beri taşıdığı bayt toplamı.
    ///
    /// Eskiden `lo0` dışındaki BÜTÜN arayüzler toplanıyordu; VPN açıkken
    /// aynı bayt hem `en0`'da hem `utun*`'da görüldüğü için trafik iki kez
    /// sayılıyordu.
    static func current() -> (received: UInt64, sent: UInt64) {
        physicalSamples().reduce(into: (received: UInt64(0), sent: UInt64(0))) { total, sample in
            total.received = total.received.saturatingAdding(sample.received)
            total.sent = total.sent.saturatingAdding(sample.sent)
        }
    }

    /// Trafiği taşıyan birincil arayüzün adı ve IPv4 adresi. En çok bayt
    /// taşıyan arayüz seçiliyor — makinede aynı anda birkaç tanesi ayakta
    /// olabiliyor (Wi-Fi + VPN + sanal köprüler) ve "etkin olan" başka
    /// türlü ayırt edilemiyor.
    static func primaryInterface() -> (name: String, address: String) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return ("", "") }
        defer { freeifaddrs(addresses) }

        var busiest: (name: String, bytes: UInt64) = ("", 0)
        var ipv4: [String: String] = [:]

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: pointer.pointee.ifa_name)
            guard name != "lo0", let family = pointer.pointee.ifa_addr?.pointee.sa_family else {
                continue
            }

            if family == UInt8(AF_LINK) {
                guard let data = pointer.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else {
                    continue
                }
                let total = UInt64(data.pointee.ifi_ibytes) &+ UInt64(data.pointee.ifi_obytes)
                if total > busiest.bytes {
                    busiest = (name, total)
                }
            } else if family == UInt8(AF_INET), let addr = pointer.pointee.ifa_addr {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addr, socklen_t(addr.pointee.sa_len),
                    &host, socklen_t(host.count),
                    nil, 0, NI_NUMERICHOST
                ) == 0 {
                    ipv4[name] = String(cString: host)
                }
            }
        }

        return (busiest.name, ipv4[busiest.name] ?? "")
    }

    /// VPN arayüzleri (`utun*`, `ipsec*`, `ppp*`) ayakta ve adres taşıyor mu.
    /// macOS bağlantının "VPN olduğunu" ayrıca bildirmiyor; arayüz adı
    /// elimizdeki tek işaret.
    static func isVPNActive() -> Bool {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return false }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: pointer.pointee.ifa_name)
            let isTunnel = name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")
            guard isTunnel,
                  pointer.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET),
                  pointer.pointee.ifa_flags & UInt32(IFF_UP) != 0
            else { continue }
            return true
        }
        return false
    }
}
