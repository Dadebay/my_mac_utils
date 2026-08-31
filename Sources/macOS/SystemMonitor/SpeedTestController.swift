import Foundation

/// Cloudflare'in açık ölçüm uç noktalarına karşı indirme/yükleme hızı ve
/// gecikme ölçer.
///
/// Ölçüm süreye bağlı, boyuta değil: bağlantı ne kadar hızlıysa o kadar çok
/// bayt iner, oran hep aynı pencereden hesaplanır. Sabit boyutlu bir dosya
/// kullanılsaydı hızlı bağlantılarda test bir saniyede biter ve TCP yavaş
/// başlangıcı sonucun tamamına karışırdı.
@MainActor
@Observable
final class SpeedTestController {
    /// Panel ile ana pencere arasında geçiş yapıldığında son sonuç
    /// kaybolmasın diye tekil.
    static let shared = SpeedTestController()

    enum Phase: Equatable {
        case idle
        case latency
        case download
        case upload
        case finished
        case cancelled
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// En düşük gidiş-dönüş süresi (ms) — jitter'dan arındırılmış taban.
    private(set) var latencyMs: Double?
    private(set) var jitterMs: Double?
    private(set) var downloadBitsPerSecond: Double?
    private(set) var uploadBitsPerSecond: Double?
    /// Ölçüm sürerken canlı gösterilen anlık oran.
    private(set) var liveBitsPerSecond: Double = 0
    /// Aktif aşamanın 0…1 arası ilerlemesi.
    private(set) var progress: Double = 0
    private(set) var finishedAt: Date?
    /// Testin ürettiği toplam trafik — geçmişe de yazıldığı için kullanıcıya
    /// söylenebilsin diye tutuluyor.
    private(set) var lastRunBytes: UInt64 = 0

    var isRunning: Bool {
        switch phase {
        case .latency, .download, .upload: true
        default: false
        }
    }

    private var runTask: _Concurrency.Task<Void, Never>?

    // MARK: - Ayarlar

    private enum Config {
        static let host = "https://speed.cloudflare.com"
        /// Ölçüm penceresi. Sekiz saniye, TCP'nin tam hıza çıkması için
        /// yeterli ve kullanıcıyı bekletmeyecek kadar kısa.
        static let measureSeconds: Double = 8
        /// İlk yarım saniye sayılmaz — yavaş başlangıç ve TLS el sıkışması
        /// gerçek hızı olduğundan düşük gösterir.
        static let warmupSeconds: Double = 0.5
        /// Cloudflare `__down` uç noktası 100.000.000 bayt ve üstündeki
        /// istekleri reddedip tek bayt döndürüyor — ölçülerek bulundu,
        /// güvenli tarafta kalınıyor.
        static let downloadChunkBytes = 90_000_000
        /// Yükleme parça parça gönderilir; tek seferde bellekte tutulan
        /// miktar bu kadarla sınırlı kalsın.
        static let uploadChunkBytes = 8 * 1024 * 1024
        /// Testin harcayabileceği en fazla veri. Hızlı bir bağlantıda ölçüm
        /// penceresi dolmadan parçalar arka arkaya biteceği için üst sınır
        /// olmasa gigabaytlar akardı.
        static let downloadBudgetBytes = 250_000_000
        static let uploadBudgetBytes = 100_000_000
        static let latencySamples = 5
        static let pollInterval: Duration = .milliseconds(120)
    }

    // MARK: - Yaşam döngüsü

    func start() {
        guard !isRunning else { return }

        runTask?.cancel()
        latencyMs = nil
        jitterMs = nil
        downloadBitsPerSecond = nil
        uploadBitsPerSecond = nil
        liveBitsPerSecond = 0
        progress = 0
        lastRunBytes = 0
        finishedAt = nil

        runTask = _Concurrency.Task { [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        if isRunning {
            phase = .cancelled
            liveBitsPerSecond = 0
            progress = 0
        }
    }

    private func run() async {
        let session = Self.makeSession()
        // Oturum temsilciyi güçlü tutar; sızmaması için her koşuda kapatılır.
        defer { session.finishTasksAndInvalidate() }

        do {
            phase = .latency
            let latency = try await measureLatency(session: session)
            guard !_Concurrency.Task.isCancelled else { return markCancelled() }
            latencyMs = latency.min
            jitterMs = latency.jitter

            phase = .download
            progress = 0
            let download = try await measureDownload(session: session)
            guard !_Concurrency.Task.isCancelled else { return markCancelled() }
            downloadBitsPerSecond = download

            phase = .upload
            progress = 0
            liveBitsPerSecond = 0
            let upload = try await measureUpload(session: session)
            guard !_Concurrency.Task.isCancelled else { return markCancelled() }
            uploadBitsPerSecond = upload

            liveBitsPerSecond = 0
            progress = 0
            finishedAt = Date()
            phase = .finished
        } catch is CancellationError {
            markCancelled()
        } catch {
            liveBitsPerSecond = 0
            progress = 0
            phase = .failed((error as NSError).localizedDescription)
        }
    }

    private func markCancelled() {
        liveBitsPerSecond = 0
        progress = 0
        phase = .cancelled
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // Önbellekten servis edilen bir yanıt ölçümü anlamsız kılar.
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: - Gecikme

    /// Aynı oturumda art arda küçük istekler; bağlantı yeniden kullanıldığı
    /// için ilk isteğin el sıkışma maliyeti sonrakilere yansımaz. Taban
    /// değer olarak en düşüğü alınır — ortalama, tek bir tıkanma anıyla
    /// bozulur.
    private func measureLatency(session: URLSession) async throws -> (min: Double, jitter: Double) {
        var samples: [Double] = []

        for index in 0..<Config.latencySamples {
            try _Concurrency.Task.checkCancellation()

            var request = URLRequest(url: URL(string: "\(Config.host)/__down?bytes=0")!)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            let start = ContinuousClock.now
            _ = try await session.data(for: request)
            let elapsed = ContinuousClock.now - start

            // İlk örnek el sıkışmayı içerir, ölçüme katılmaz.
            if index > 0 {
                samples.append(elapsed.milliseconds)
            }
            progress = Double(index + 1) / Double(Config.latencySamples)
        }

        guard let minimum = samples.min() else { return (0, 0) }

        // Jitter: ardışık örnekler arasındaki ortalama mutlak fark.
        let deltas = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
        let jitter = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)

        return (minimum, jitter)
    }

    // MARK: - İndirme / Yükleme

    private func measureDownload(session: URLSession) async throws -> Double {
        var request = URLRequest(
            url: URL(string: "\(Config.host)/__down?bytes=\(Config.downloadChunkBytes)")!
        )
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        return try await measureThroughput(budget: Config.downloadBudgetBytes) { delegate in
            let task = session.dataTask(with: request)
            task.delegate = delegate
            return task
        }
    }

    private func measureUpload(session: URLSession) async throws -> Double {
        var request = URLRequest(url: URL(string: "\(Config.host)/__up")!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let payload = Data(count: Config.uploadChunkBytes)

        return try await measureThroughput(budget: Config.uploadBudgetBytes) { delegate in
            let task = session.uploadTask(with: request, from: payload)
            task.delegate = delegate
            return task
        }
    }

    // MARK: - Ortak ölçüm döngüsü

    /// Ölçüm penceresi dolana ya da veri bütçesi bitene kadar ardışık
    /// istekler açar ve inen/çıkan baytları sayar.
    ///
    /// Parçalı olması şart: tek bir istek yavaş bağlantıda süre dolmadan
    /// bitmez ama hızlı bağlantıda bir saniyede biter ve geriye ölçülecek
    /// bir şey kalmaz. Oran, ısınma penceresinden sonraki dilimden
    /// hesaplanır — TCP yavaş başlangıcı sonuca karışmasın.
    private func measureThroughput(
        budget: Int,
        makeTask: (ByteCountingDelegate) -> URLSessionTask
    ) async throws -> Double {
        let counter = ByteCounter()
        let delegate = ByteCountingDelegate(counter: counter)

        let started = ContinuousClock.now
        let deadline = started + .seconds(Config.measureSeconds + Config.warmupSeconds)
        var baseline: (bytes: Int, at: ContinuousClock.Instant)?
        var lastRate: Double = 0

        defer { lastRunBytes &+= UInt64(counter.current) }

        while ContinuousClock.now < deadline, counter.current < budget {
            try _Concurrency.Task.checkCancellation()

            let task = makeTask(delegate)
            task.resume()

            // `.completed` hem normal bitişi hem iptali/hatayı kapsar.
            while task.state != .completed {
                try await _Concurrency.Task.sleep(for: Config.pollInterval)
                if _Concurrency.Task.isCancelled {
                    task.cancel()
                    throw CancellationError()
                }

                let now = ContinuousClock.now
                let elapsed = (now - started).seconds

                if baseline == nil, elapsed >= Config.warmupSeconds {
                    baseline = (counter.current, now)
                }

                if let baseline {
                    let window = (now - baseline.at).seconds
                    if window > 0.2 {
                        lastRate = Double(counter.current - baseline.bytes) * 8 / window
                        liveBitsPerSecond = lastRate
                    }
                }

                progress = min(elapsed / (Config.measureSeconds + Config.warmupSeconds), 1)

                if now >= deadline || counter.current >= budget {
                    task.cancel()
                    break
                }
            }
        }

        // Isınma penceresine hiç girilemediyse toplam bayt / toplam süre
        // yine de kullanılabilir bir tahmin verir.
        if lastRate == 0 {
            let elapsed = (ContinuousClock.now - started).seconds
            return elapsed > 0 ? Double(counter.current) * 8 / elapsed : 0
        }
        return lastRate
    }
}

// MARK: - Sayaç ve temsilci

/// Ağ temsilcisi arka plan kuyruğundan yazar, ana aktör okur — erişim
/// kilitle korunuyor.
private final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func add(_ amount: Int) {
        lock.lock()
        value += amount
        lock.unlock()
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// İnen baytları ve giden gövde baytlarını aynı sayaca yazar.
private final class ByteCountingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let counter: ByteCounter

    init(counter: ByteCounter) {
        self.counter = counter
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        counter.add(data.count)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        counter.add(Int(bytesSent))
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    var milliseconds: Double { seconds * 1000 }
}
