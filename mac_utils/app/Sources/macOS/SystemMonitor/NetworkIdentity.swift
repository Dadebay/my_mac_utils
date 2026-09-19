import Darwin
import Foundation
import SystemConfiguration

/// Ayakta olan VPN tünelinin ayrıntısı.
///
/// macOS bir bağlantının "VPN olduğunu" doğrudan bildirmiyor; elimizdeki
/// işaretler arayüz adı (`utun*`, `ipsec*`, `ppp*`) ve — varsa — Sistem
/// Ayarları'ndaki servis adı. WireGuard, Tailscale gibi kendi tünelini
/// kuran uygulamaların Sistem Ayarları'nda bir servisi olmuyor; onlarda
/// gösterilebilecek en doğru ad arayüzün kendisi.
struct VPNDetail: Equatable, Sendable {
    var isActive = false
    /// Sistem Ayarları'ndaki VPN servisinin adı — yalnızca sistem VPN'leri.
    var serviceName: String?
    /// Tüneli kuran uygulamanın adı — kendi paket tüneli uzantısını
    /// çalıştıran VPN uygulamaları (Happ, WireGuard, Tailscale…).
    var appName: String?
    /// Tünel arayüzü: `utun4`, `ppp0`…
    var interfaceName: String?
    /// Tünelin taşıdığı yerel adres.
    var address: String?

    /// Kullanıcıya gösterilecek ad. Sıra kasıtlı: sistem VPN servisinin
    /// adını kullanıcı kendisi yazmıştır, en doğru karşılık odur; yoksa
    /// tüneli kuran uygulamanın adı; o da yoksa arayüzün kendisi.
    var displayName: String? {
        serviceName ?? appName ?? interfaceName
    }
}

/// Makinenin ağ kimliği: yerel adres, VPN durumu ve dışarıya görünen adres.
///
/// Genel adres yalnızca dışarıya sorularak öğrenilebiliyor — makinenin
/// kendisi NAT'ın arkasındaki adresini biliyor, internetin onu hangi
/// adresle gördüğünü bilmiyor. Bu yüzden burada tek bir dış istek var ve
/// ne zaman yapıldığı belli: sayfa açıldığında bir kez, sonra yalnızca
/// VPN durumu değiştiğinde ya da kullanıcı tazelediğinde.
@MainActor
@Observable
final class NetworkIdentityController {
    static let shared = NetworkIdentityController()

    private(set) var vpn = VPNDetail()
    private(set) var publicAddress: String?
    /// Ülke kodu — VPN'in nereye çıktığını tek bakışta söylüyor.
    private(set) var publicRegion: String?
    private(set) var isLookingUp = false
    private(set) var lookupFailed = false

    /// Son sorgunun dayandığı VPN durumu. Tünel değişince adres de
    /// değişmiş demektir; sorgu o zaman tekrarlanıyor.
    private var lookedUpFor: VPNDetail?

    private init() {}

    /// Sayfa göründüğünde çağrılıyor. Zaten bilinen ve VPN durumu
    /// değişmemişse ağa çıkmıyor.
    func refreshIfNeeded() async {
        let current = await resolveVPN()
        vpn = current

        if publicAddress != nil, lookedUpFor == current { return }
        await lookUpPublicAddress(for: current)
    }

    func refresh() async {
        vpn = await resolveVPN()
        await lookUpPublicAddress(for: vpn)
    }

    /// Ucuz kısım (arayüz taraması) hemen, pahalı kısım (süreç listesini
    /// tarayıp sağlayıcıyı bulmak) yalnızca gerçekten bir tünel varken ve
    /// sistem VPN'i olarak adlandırılamadıysa — o da ana iş parçacığının
    /// dışında.
    private func resolveVPN() async -> VPNDetail {
        var detail = Self.detectVPN()
        guard detail.isActive, detail.serviceName == nil else { return detail }
        detail.appName = await _Concurrency.Task.detached(priority: .utility) {
            Self.tunnelProviderAppName()
        }.value
        return detail
    }

    private func lookUpPublicAddress(for detail: VPNDetail) async {
        guard !isLookingUp else { return }
        isLookingUp = true
        lookupFailed = false
        defer { isLookingUp = false }

        guard let trace = await Self.fetchTrace() else {
            lookupFailed = true
            return
        }

        publicAddress = trace.ip
        publicRegion = trace.region
        lookedUpFor = detail
    }

    // MARK: - Dış adres

    /// Cloudflare'ın `cdn-cgi/trace` ucu: düz metin `anahtar=değer`
    /// satırları döndürüyor ve hesap/anahtar istemiyor. Bir "IP öğrenme
    /// servisi" yerine bunun seçilmesinin sebebi, isteğin bir izleme
    /// hizmetine değil zaten internetin altyapısında duran bir CDN'e
    /// gitmesi.
    private nonisolated static func fetchTrace() async -> (ip: String, region: String?)? {
        guard let url = URL(string: "https://www.cloudflare.com/cdn-cgi/trace") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        // Önbellek dışarıya görünen adresi eskitebilir: VPN açılıp
        // kapandığında eski yanıt doğru sanılırdı.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        var ip: String?
        var region: String?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "ip": ip = String(parts[1])
            case "loc": region = String(parts[1])
            default: break
            }
        }

        guard let ip else { return nil }
        return (ip, region)
    }

    // MARK: - VPN

    static func detectVPN() -> VPNDetail {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return VPNDetail() }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: pointer.pointee.ifa_name)
            let isTunnel = name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")
            guard isTunnel,
                  let addr = pointer.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  pointer.pointee.ifa_flags & UInt32(IFF_UP) != 0
            else { continue }

            return VPNDetail(
                isActive: true,
                serviceName: serviceName(forBSDName: name),
                interfaceName: name,
                address: ipv4String(from: addr)
            )
        }

        return VPNDetail()
    }

    private static func ipv4String(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            addr,
            socklen_t(addr.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: host)
    }

    // MARK: - Tüneli kuran uygulama

    /// Tüneli kuran uygulamanın adı.
    ///
    /// macOS "bu `utun` arayüzünü kim açtı" sorusunu yanıtlamıyor. Ama
    /// modern macOS'ta bir VPN uygulaması tüneli ancak NetworkExtension
    /// paket tüneli üzerinden kurabiliyor ve o uzantı, uygulamanın
    /// içinden ayrı bir süreç olarak çalışıyor. Çalışan süreçlerin
    /// yollarında paket tüneli uzantısını arıyoruz; bulunca yolun
    /// içindeki `.app` zaten uygulamanın kendisi:
    ///
    ///     /Applications/Happ.app/Contents/PlugIns/Tunnel.appex/…
    ///
    /// Uzantının türü Info.plist'ten doğrulanıyor — ada bakan bir tahmin
    /// değil. Bu yüzden yalnızca bilinen VPN'leri değil, bu yolla tünel
    /// kuran her uygulamayı tanıyor.
    ///
    /// Sandbox'ta başka süreçlerin yolu ve başka paketlerin Info.plist'i
    /// okunamıyor; orada sessizce boş dönüp arayüz adına düşülüyor.
    private nonisolated static func tunnelProviderAppName() -> String? {
        for path in runningExecutablePaths() {
            guard let range = path.range(of: ".appex/") else { continue }
            let appex = URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".appex")
            guard isPacketTunnel(appex) else { continue }
            return owningAppName(for: appex)
        }
        return nil
    }

    private nonisolated static func runningExecutablePaths() -> [String] {
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&request, 4, nil, &length, nil, 0) == 0, length > 0 else { return [] }

        let capacity = length / MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        guard sysctl(&request, 4, &processes, &length, nil, 0) == 0 else { return [] }

        var paths: [String] = []
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for index in 0..<min(capacity, length / MemoryLayout<kinfo_proc>.stride) {
            let pid = processes[index].kp_proc.p_pid
            guard pid > 0, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            paths.append(String(cString: buffer))
        }
        return paths
    }

    private nonisolated static func isPacketTunnel(_ appex: URL) -> Bool {
        let plist = appex.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = root as? [String: Any],
              let extensionInfo = info["NSExtension"] as? [String: Any],
              let point = extensionInfo["NSExtensionPointIdentifier"] as? String
        else { return false }
        return point == "com.apple.networkextension.packet-tunnel"
    }

    /// Uzantıyı barındıran `.app`in kullanıcıya görünen adı.
    private nonisolated static func owningAppName(for appex: URL) -> String? {
        var url = appex
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            guard url.pathExtension == "app" else { continue }
            let bundle = Bundle(url: url)
            let display = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            return display ?? name ?? url.deletingPathExtension().lastPathComponent
        }
        return nil
    }

    /// Sistem Ayarları'ndaki VPN servisinin kullanıcıya görünen adı.
    ///
    /// Yalnızca macOS'un kendi kurduğu bağlantılarda (IKEv2, L2TP, IPsec)
    /// bir karşılık var; kendi tünelini kuran uygulamalarda burası boş
    /// dönüyor ve arayüz adına düşülüyor. Sandbox'ta okuma başarısız
    /// olursa da aynı yola düşüyor — bu yüzden her adım isteğe bağlı.
    private static func serviceName(forBSDName bsdName: String) -> String? {
        guard let preferences = SCPreferencesCreate(nil, "GlassDo" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(preferences),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService]
        else { return nil }

        for service in services {
            guard SCNetworkServiceGetEnabled(service),
                  let interface = SCNetworkServiceGetInterface(service),
                  let name = SCNetworkInterfaceGetBSDName(interface) as String?,
                  name == bsdName,
                  let serviceName = SCNetworkServiceGetName(service) as String?
            else { continue }
            return serviceName
        }

        return nil
    }
}
