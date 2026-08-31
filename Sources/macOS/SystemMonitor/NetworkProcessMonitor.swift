import AppKit
import Foundation

/// Tek bir sürecin ölçülen ağ kullanımı.
///
/// Sayaçlar sürecin kendi ömrü boyunca birikir — `nettop` anlık hız değil,
/// o güne kadarki toplamı bildirir. Bu yüzden liste "şu an kim indiriyor"
/// değil, "bu oturumda kim ne kadar harcadı" sorusunu yanıtlar.
struct NetworkProcessUsage: Identifiable, Equatable, Sendable {
    let pid: pid_t
    /// `nettop`'un bildirdiği süreç adı. Çekirdek süreç adlarını 15
    /// karakterde kırpıyor ("nesessionmanage"), bu yüzden kullanıcıya
    /// gösterilen ad mümkün olduğunda `NSRunningApplication`dan alınır.
    let processName: String
    let bytesIn: UInt64
    let bytesOut: UInt64

    var id: pid_t { pid }
    var total: UInt64 { bytesIn &+ bytesOut }
}

/// `nettop` çağrısı. Ana aktörden ayrı çalıştırılabilsin diye durumsuz:
/// `Process` ve `Pipe` Sendable değil, ikisi de bu fonksiyonun içinde
/// doğup ölüyor.
enum NetworkProcessSampler {
    /// Tek bir örnek. Başarısızlıkta nil — çağıran sakin bir mesaj gösterir,
    /// çünkü `nettop` bazı sistemlerde yetki ya da politika nedeniyle hiç
    /// çalışmayabiliyor ve bu bir çökme sebebi değil.
    static func sample() -> [NetworkProcessUsage]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -P süreç başına toplar, -L 1 tek örnek alıp çıkar, -n adları
        // çözmeye çalışmaz, -x ham bayt verir (insan için kısaltmaz).
        process.arguments = ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]

        let pipe = Pipe()
        process.standardOutput = pipe
        // Hata çıktısı boruyu doldurup süreci kilitlemesin.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Önce oku, sonra bekle: ters sırada boru tamponu dolduğunda
        // `nettop` yazmayı bitiremez ve iki taraf da birbirini bekler.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)
        else { return nil }

        return parse(output)
    }

    /// CSV satırları `Süreç Adı.PID,bytes_in,bytes_out,` biçiminde gelir.
    /// Süreç adının kendisinde de nokta olabildiği için ("com.apple.WebKit")
    /// PID **son** noktadan sonrası kabul ediliyor.
    static func parse(_ output: String) -> [NetworkProcessUsage] {
        var rows: [NetworkProcessUsage] = []

        for line in output.split(separator: "\n") {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }

            let identifier = columns[0].trimmingCharacters(in: .whitespaces)
            guard let dot = identifier.lastIndex(of: "."),
                  let pid = pid_t(identifier[identifier.index(after: dot)...])
            else { continue }

            let name = String(identifier[..<dot])
            guard !name.isEmpty,
                  let bytesIn = UInt64(columns[1].trimmingCharacters(in: .whitespaces)),
                  let bytesOut = UInt64(columns[2].trimmingCharacters(in: .whitespaces))
            else { continue }

            // Hiç trafiği olmayan süreçler listeyi doldurmaktan başka bir
            // şey yapmıyor; ilk beşe girmelerinin de imkânı yok.
            guard bytesIn &+ bytesOut > 0 else { continue }

            rows.append(
                NetworkProcessUsage(
                    pid: pid,
                    processName: name,
                    bytesIn: bytesIn,
                    bytesOut: bytesOut
                )
            )
        }

        return rows.sorted { $0.total > $1.total }
    }
}

/// Süreç bazlı ağ kullanımını periyodik olarak toplar.
///
/// Ölçüm `nettop`'un ayrı bir süreç olarak çalıştırılmasıyla yapılıyor ve
/// bir örnek yaklaşık bir saniye sürüyor; bu yüzden çağrı ana aktörde değil,
/// `Task.detached` içinde. Ana aktöre yalnızca sonuç dönüyor.
///
/// `SystemStatsController` ile aynı sayaçlı abonelik: panel kapanınca son
/// abone de düşer ve döngü durur — kimse bakmıyorken saniyede bir süreç
/// başlatmanın karşılığı yok.
@MainActor
@Observable
final class NetworkProcessMonitor {
    static let shared = NetworkProcessMonitor()

    /// Panelde gösterilen satır sayısı.
    static let displayLimit = 5

    /// `nettop` bir örnek için ~1 saniye harcıyor; dört saniyeden sık
    /// yenilemek ölçümün kendisiyle yarışmak olurdu.
    private static let refreshInterval: Duration = .seconds(4)

    /// Toplam kullanıma göre büyükten küçüğe, ilk `displayLimit` satır.
    private(set) var processes: [NetworkProcessUsage] = []
    /// `nettop` çalıştırılamadığında true. Panel bunu sakin bir satırla
    /// gösteriyor — ölçüm alınamaması uygulamanın hatası değil.
    private(set) var isUnavailable = false
    /// İlk örnek gelmeden "trafik yok" demek yanlış olurdu.
    private(set) var hasSampled = false

    private var pollTask: _Concurrency.Task<Void, Never>?
    private var subscribers = 0

    /// Bir tüketici listeye abone olur. İlk abone döngüyü başlatır.
    func start() {
        subscribers += 1
        guard pollTask == nil else { return }

        pollTask = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                await self?.sampleOnce()
                guard !_Concurrency.Task.isCancelled else { return }
                try? await _Concurrency.Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    /// Son abone bırakınca ölçüm duruyor.
    func stop() {
        subscribers = max(subscribers - 1, 0)
        guard subscribers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    /// Döngü sıralı: bir örnek bitmeden ötekine başlanmıyor, yani aynı anda
    /// birden fazla `nettop` süreci hiç olmuyor.
    private func sampleOnce() async {
        let sampled = await _Concurrency.Task.detached(priority: .utility) {
            NetworkProcessSampler.sample()
        }.value

        guard !_Concurrency.Task.isCancelled else { return }

        guard let sampled else {
            isUnavailable = true
            hasSampled = true
            return
        }

        isUnavailable = false
        hasSampled = true
        processes = Array(sampled.prefix(Self.displayLimit))
    }
}

/// Bir satırın kullanıcıya görünen hâli: ad, ikon ve süreçle ne
/// yapılabileceği. `NSRunningApplication` yalnızca ana aktörden okunabildiği
/// için ölçüm modelinden ayrı tutuluyor.
@MainActor
struct NetworkProcessPresentation {
    let usage: NetworkProcessUsage
    let application: NSRunningApplication?

    init(usage: NetworkProcessUsage) {
        self.usage = usage
        self.application = NSRunningApplication(processIdentifier: usage.pid)
    }

    /// `nettop`'un kırpılmış süreç adı yerine, varsa uygulamanın kendi adı.
    var displayName: String {
        application?.localizedName ?? usage.processName
    }

    var icon: NSImage? {
        application?.icon
    }

    /// Öne getirme ve kapatma yalnızca kullanıcının kendi uygulamalarında
    /// açık. `.regular` olmayan her şey (arka plan görevleri, ajanlar,
    /// çekirdek süreçleri) ve GlassDo'nun kendisi listede görünür ama
    /// dokunulamaz — bir sistem sürecini kapatmak kullanıcının bu panelden
    /// vermek isteyeceği bir karar değil.
    var isControllable: Bool {
        guard let application,
              application.activationPolicy == .regular,
              !application.isTerminated
        else { return false }

        // PID 1 (launchd) ve GlassDo'nun kendisi hiçbir koşulda değil.
        guard usage.pid != 1, usage.pid != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        return application.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    func activate() {
        application?.activate(options: [])
    }

    /// Nazik kapatma isteği: uygulama kaydedilmemiş işi varsa kendi
    /// soruyor. Zorla sonlandırma (`forceTerminate`) bilerek kullanılmıyor —
    /// veri kaybettirebilir.
    @discardableResult
    func requestTermination() -> Bool {
        guard isControllable, let application else { return false }
        return application.terminate()
    }
}
