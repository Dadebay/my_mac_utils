import Foundation
import IOKit
import IOKit.usb

/// USB'ye takılı bir Android cihaz.
struct AndroidDevice: Identifiable, Equatable {
    /// IORegistry girdi kimliği — cihaz takılı kaldığı sürece değişmiyor.
    let id: UInt64
    let vendorID: Int
    let productID: Int
    let vendorName: String
    let productName: String
    let serial: String?

    /// Telefonda "Dosya aktarımı" (MTP) modu seçili mi. Seçili değilken
    /// cihaz görünür ama içeriğine erişilemez — kullanıcıya söylenmesi
    /// gereken şey bu.
    let hasFileTransfer: Bool
    /// "USB hata ayıklama" açık mı (ADB arayüzü). APK yükleme gibi işler
    /// buna bağlı.
    let hasDebugging: Bool

    var displayName: String {
        let name = productName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? vendorName : name
    }
}

/// USB'ye takılan Android cihazları izler.
///
/// Cihazı tanımanın iki yolu var ve ikisi de kullanılıyor:
///
/// - **Arayüz imzası:** Telefon "Dosya aktarımı" modundayken MTP arayüzü
///   açıyor (USB görüntü sınıfı, PTP alt sınıfı); "USB hata ayıklama"
///   açıkken de ADB arayüzü (üreticiye özel sınıf, 0x42/0x01). Bu imzalar
///   markadan bağımsız, yani listede olmayan bir telefon da tanınıyor.
/// - **Üretici kimliği:** Telefon "yalnızca şarj" modundaysa hiçbir veri
///   arayüzü açmıyor. O zaman yalnızca üretici kimliğinden tanınabiliyor —
///   ve kullanıcıya "modu değiştir" demek için önce cihazı görmek gerekiyor.
@MainActor
@Observable
final class AndroidDeviceMonitor {
    static let shared = AndroidDeviceMonitor()

    private(set) var devices: [AndroidDevice] = []
    /// USB hiç sorgulanamadı — sandbox izni yoksa böyle oluyor.
    private(set) var isUnavailable = false

    private var timer: _Concurrency.Task<Void, Never>?
    private var subscribers = 0

    /// Takıp çıkarmanın fark edilmesi için yeterince sık, tarama maliyeti
    /// önemsiz kalacak kadar seyrek.
    private static let interval: Duration = .seconds(2)

    func start() {
        subscribers += 1
        guard timer == nil else { return }
        refresh()
        timer = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(for: Self.interval)
                guard !_Concurrency.Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        subscribers = max(subscribers - 1, 0)
        guard subscribers == 0 else { return }
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            isUnavailable = true
            devices = []
            return
        }
        defer { IOObjectRelease(iterator) }
        isUnavailable = false

        var found: [AndroidDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let device = Self.device(from: service) { found.append(device) }
        }

        // Sıra sabit kalsın: liste her taramada yeniden kurulduğu için
        // rastgele sıralanırsa satırlar gözün önünde yer değiştirirdi.
        found.sort { ($0.displayName, $0.id) < ($1.displayName, $1.id) }
        if found != devices { devices = found }
    }

    private static func device(from service: io_service_t) -> AndroidDevice? {
        guard let vendorID = property(service, "idVendor") as? Int,
              let productID = property(service, "idProduct") as? Int
        else { return nil }

        let interfaces = self.interfaces(of: service)
        let hasFileTransfer = interfaces.contains { $0.isMTP }
        let hasDebugging = interfaces.contains { $0.isADB }

        // Arayüz imzası yoksa yalnızca tanıdık bir üretici kimliği cihazı
        // Android saydırıyor — yoksa klavyeler, diskler, kameralar da
        // listeye girerdi.
        guard hasFileTransfer || hasDebugging || androidVendorIDs.contains(vendorID) else {
            return nil
        }

        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &entryID)

        return AndroidDevice(
            id: entryID,
            vendorID: vendorID,
            productID: productID,
            vendorName: property(service, "USB Vendor Name") as? String ?? vendorName(for: vendorID),
            productName: property(service, "USB Product Name") as? String ?? "",
            serial: property(service, "USB Serial Number") as? String,
            hasFileTransfer: hasFileTransfer,
            hasDebugging: hasDebugging
        )
    }

    private struct USBInterface {
        let classCode: Int
        let subclass: Int
        let protocolCode: Int

        /// MTP, USB'nin görüntü sınıfını (6) PTP alt sınıfıyla kullanıyor.
        var isMTP: Bool { classCode == 6 && subclass == 1 }
        /// Android'in ADB arayüzü: üreticiye özel sınıf, sabit 0x42/0x01.
        var isADB: Bool { classCode == 255 && subclass == 0x42 && protocolCode == 1 }
    }

    /// Cihazın alt düğümlerindeki USB arayüzleri. Arayüzler ayrı IORegistry
    /// girdileri; cihazın kendi özelliklerinde sınıf bilgisi yok.
    private static func interfaces(of service: io_service_t) -> [USBInterface] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [USBInterface] = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard let classCode = property(child, "bInterfaceClass") as? Int else { continue }
            result.append(USBInterface(
                classCode: classCode,
                subclass: property(child, "bInterfaceSubClass") as? Int ?? 0,
                protocolCode: property(child, "bInterfaceProtocol") as? Int ?? 0
            ))
        }
        return result
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )
    }

    /// "Yalnızca şarj" modundaki telefonları tanımak için. Eksik olması
    /// kırılgan değil: veri arayüzü açık her Android zaten imzasından
    /// tanınıyor, bu liste yalnızca sessiz moddaki cihazlar için.
    private static let androidVendorIDs: Set<Int> = [
        0x18D1, // Google / Pixel
        0x04E8, // Samsung
        0x2717, // Xiaomi
        0x2A70, // Xiaomi (POCO, Redmi)
        0x12D1, // Huawei
        0x22D9, // OPPO / OnePlus / Realme
        0x2D95, // Vivo
        0x0FCE, // Sony
        0x1004, // LG
        0x22B8, // Motorola
        0x0BB4, // HTC
        0x0B05, // Asus
        0x17EF, // Lenovo
        0x2E04, // Nokia (HMD)
        0x2916, // Android One (Android/Yulong)
        0x1BBB, // Alcatel / TCL
    ]

    private static func vendorName(for id: Int) -> String {
        switch id {
        case 0x18D1: "Google"
        case 0x04E8: "Samsung"
        case 0x2717, 0x2A70: "Xiaomi"
        case 0x12D1: "Huawei"
        case 0x22D9: "OPPO"
        case 0x2D95: "vivo"
        case 0x0FCE: "Sony"
        case 0x1004: "LG"
        case 0x22B8: "Motorola"
        case 0x0BB4: "HTC"
        case 0x0B05: "ASUS"
        case 0x17EF: "Lenovo"
        case 0x2E04: "Nokia"
        case 0x1BBB: "TCL"
        default: "Android"
        }
    }
}
