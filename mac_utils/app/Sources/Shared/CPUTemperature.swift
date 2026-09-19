import Foundation
import IOKit

/// İşlemci sıcaklığı.
///
/// macOS bu değeri belgelenmiş hiçbir API'yle vermiyor. İki yol var ve
/// ikisi de özel (private):
///
/// - **Apple Silicon:** `IOHIDEventSystemClient` üzerinden sıcaklık sensörü
///   servisleri. Sembol adları `IOKit` içinde var ama başlık dosyalarında
///   yayımlanmıyor, o yüzden `dlsym` ile çözülüyorlar — bulunamazlarsa
///   ölçüm sessizce kapanıyor, uygulama çökmüyor.
/// - **Intel:** `AppleSMC` sürücüsüne yapılan yapı çağrısı (`TC0P` / `TC0D`).
///
/// Sonuç: bu kod App Store'a giremez ve bir macOS güncellemesi sembolleri
/// ya da sensör adlarını değiştirirse ölçüm sessizce nil'e düşer. Bu kabul
/// edilmiş bir maliyet — alternatifi derece göstermemek.
enum CPUTemperature {
    /// Santigrat derece, okunamazsa nil.
    static func current() -> Double? {
        AppleSiliconSensors.shared.cpuTemperature() ?? SMCSensor.shared.cpuTemperature()
    }

    /// Depolamanın (NAND) sıcaklığı — yalnızca Apple Silicon'da var.
    static func storage() -> Double? {
        AppleSiliconSensors.shared.storageTemperature()
    }

    /// Sensör okumaları bazen tamamen anlamsız değerler döndürüyor
    /// (`PMU tdev*` sensörleri -9200 gibi). Fiziksel olarak mümkün
    /// aralığın dışındakiler eleniyor.
    static func isPlausible(_ value: Double) -> Bool {
        value > 0 && value < 130
    }
}

// MARK: - Apple Silicon (IOHIDEventSystemClient)

/// Sensör istemcisi bir kez kurulup saklanıyor: her ölçümde yeniden
/// yaratmak hem pahalı hem de servis listesini baştan taramak demek.
///
/// İki iş parçacığından (menü çubuğu örnekleyicisi ve widget süreci)
/// çağrılabildiği için erişim kilitle korunuyor.
private final class AppleSiliconSensors: @unchecked Sendable {
    static let shared = AppleSiliconSensors()

    private let lock = NSLock()
    private var client: AnyObject?
    private var services: [AnyObject] = []
    private var isUnavailable = false

    /// Çekirdek kümelerinin sıcaklığı. Tek bir sayı gösterileceği için
    /// **en sıcak** die sensörü seçiliyor: "işlemci ne kadar ısındı"
    /// sorusunun cevabı ortalama değil, tepe değerdir.
    func cpuTemperature() -> Double? {
        let readings = read()
        guard !readings.isEmpty else { return nil }

        // M3/M4 kuşağında çekirdek sensörleri "PMU tdieN", M1/M2'de
        // "pACC/eACC MTR Temp Sensor" diye adlandırılıyor. İkisi de yoksa
        // SoC sensörleri son çare.
        for prefix in ["PMU tdie", "pACC", "eACC", "SOC MTR", "PMU tcal"] {
            let matching = readings
                .filter { $0.name.hasPrefix(prefix) }
                .map(\.value)
            if let peak = matching.max() { return peak }
        }
        return nil
    }

    func storageTemperature() -> Double? {
        read()
            .filter { $0.name.hasPrefix("NAND") }
            .map(\.value)
            .max()
    }

    private func read() -> [(name: String, value: Double)] {
        lock.lock()
        defer { lock.unlock() }

        guard !isUnavailable else { return [] }
        if client == nil { connect() }
        guard client != nil, !services.isEmpty, let api = SensorAPI.shared else { return [] }

        var readings: [(name: String, value: Double)] = []
        readings.reserveCapacity(services.count)

        for service in services {
            guard let name = api.copyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String,
                  let event = api.copyEvent(service, SensorAPI.temperatureEventType, 0, 0)?
                .takeRetainedValue()
            else { continue }

            let value = api.floatValue(event, SensorAPI.temperatureField)
            guard CPUTemperature.isPlausible(value) else { continue }
            readings.append((name, value))
        }

        return readings
    }

    private func connect() {
        guard let api = SensorAPI.shared,
              let created = api.create(kCFAllocatorDefault)?.takeRetainedValue()
        else {
            isUnavailable = true
            return
        }

        // Apple satıcı sayfası (0xff00) altındaki 5 numaralı kullanım
        // sıcaklık sensörlerini işaret ediyor.
        let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        _ = api.setMatching(created, matching as CFDictionary)

        guard let found = api.copyServices(created)?.takeRetainedValue() as? [AnyObject],
              !found.isEmpty
        else {
            isUnavailable = true
            return
        }

        client = created
        services = found
    }
}

/// `IOKit` içinde var olan ama başlıkla yayımlanmayan sembollerin
/// çalışma zamanında çözülmüş hâli. Biri bile bulunamazsa tür `nil` olur
/// ve sıcaklık ölçümü tamamen devre dışı kalır.
private struct SensorAPI: @unchecked Sendable {
    typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    typealias SetMatching = @convention(c) (AnyObject?, CFDictionary?) -> Int32
    typealias CopyServices = @convention(c) (AnyObject?) -> Unmanaged<CFArray>?
    typealias CopyProperty = @convention(c) (AnyObject?, CFString) -> Unmanaged<AnyObject>?
    typealias CopyEvent = @convention(c) (AnyObject?, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    typealias FloatValue = @convention(c) (AnyObject?, Int32) -> Double

    static let temperatureEventType: Int64 = 15
    static let temperatureField = Int32(15 << 16)

    let create: Create
    let setMatching: SetMatching
    let copyServices: CopyServices
    let copyProperty: CopyProperty
    let copyEvent: CopyEvent
    let floatValue: FloatValue

    static let shared: SensorAPI? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        else { return nil }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        guard let create = symbol("IOHIDEventSystemClientCreate", as: Create.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let floatValue = symbol("IOHIDEventGetFloatValue", as: FloatValue.self)
        else { return nil }

        return SensorAPI(
            create: create,
            setMatching: setMatching,
            copyServices: copyServices,
            copyProperty: copyProperty,
            copyEvent: copyEvent,
            floatValue: floatValue
        )
    }()
}

// MARK: - Intel (AppleSMC)

/// Intel Mac'lerde sıcaklık `AppleSMC` sürücüsünden okunur. Apple
/// Silicon'da bu anahtarlar bulunmadığı için ilk denemede nil dönüp
/// bir daha denenmiyor.
private final class SMCSensor: @unchecked Sendable {
    static let shared = SMCSensor()

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var isUnavailable = false

    /// `TC0P` işlemci yakını, `TC0D` ise die sıcaklığı. Makineye göre
    /// yalnızca biri bulunabiliyor.
    func cpuTemperature() -> Double? {
        lock.lock()
        defer { lock.unlock() }

        guard !isUnavailable else { return nil }
        guard open() else { return nil }

        for key in ["TC0P", "TC0D", "TCXC", "TC0E"] {
            if let value = readKey(key), CPUTemperature.isPlausible(value) {
                return value
            }
        }
        isUnavailable = true
        return nil
    }

    private func open() -> Bool {
        guard connection == 0 else { return true }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else {
            isUnavailable = true
            return false
        }
        defer { IOObjectRelease(service) }

        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            isUnavailable = true
            connection = 0
            return false
        }
        return true
    }

    private func readKey(_ key: String) -> Double? {
        var info = SMCParameter()
        info.key = Self.code(key)
        info.data8 = Self.getKeyInfo

        guard var output = call(info) else { return nil }

        var read = SMCParameter()
        read.key = Self.code(key)
        read.keyInfo = output.keyInfo
        read.data8 = Self.readKey

        guard let result = call(read) else { return nil }
        output = result

        // "sp78": işaretli, kesir kısmı 8 bit sabit noktalı.
        // "flt ": doğrudan 32 bit kayan nokta.
        let type = Self.string(from: output.keyInfo.dataType)
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0) }

        switch type {
        case "sp78" where output.keyInfo.dataSize >= 2:
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "flt " where output.keyInfo.dataSize >= 4:
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        default:
            return nil
        }
    }

    private func call(_ input: SMCParameter) -> SMCParameter? {
        var input = input
        var output = SMCParameter()
        var outputSize = MemoryLayout<SMCParameter>.stride

        let result = IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<SMCParameter>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private static let getKeyInfo: UInt8 = 9
    private static let readKey: UInt8 = 5

    /// SMC anahtarları dört harflik ASCII kodlar; sürücü onları tek bir
    /// 32 bitlik sayı olarak bekliyor.
    private static func code(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// `AppleSMC` sürücüsünün beklediği yapı. Alan sırası ve boyutu sürücü
/// tarafından sabitlenmiş — değiştirilemez.
private struct SMCParameter {
    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PowerLimit {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PowerLimit()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
