import AppKit
import AVFoundation
import Foundation
import GlassDoKit

/// Telefondaki tek bir dosya ya da klasör.
struct AndroidFile: Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    /// Bağlantının gösterdiği yol — `/sdcard` gibi girişlerin çoğu bağlantı.
    let linkTarget: String?
    let size: UInt64
    let modified: String

    /// Bağlantılar da klasör gibi açılmayı deniyor: hedefin klasör olup
    /// olmadığını `ls` söylemiyor, denemek tek yol.
    var isOpenable: Bool { isDirectory || linkTarget != nil }

    /// Önizlemesi kareden çıkarılabilecek bir video mu.
    var isVideo: Bool {
        guard !isOpenable else { return false }
        return ["mp4", "mov", "m4v", "3gp", "mkv", "avi", "webm"]
            .contains((name as NSString).pathExtension.lowercased())
    }

    /// Önizlemesi gösterilebilecek bir resim mi.
    var isImage: Bool {
        guard !isOpenable else { return false }
        return ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp"]
            .contains((name as NSString).pathExtension.lowercased())
    }
}

/// Telefonun depolama durumu.
struct AndroidStorage: Equatable {
    let total: UInt64
    let used: UInt64
    let free: UInt64

    /// Dolu oran, 0…1. Çubuk bunu çiziyor.
    var usedFraction: Double {
        total > 0 ? min(Double(used) / Double(total), 1) : 0
    }
}

/// Süren bir aktarmanın durumu.
struct AndroidTransfer: Equatable {
    let name: String
    /// Şimdiye kadar aktarılan bayt. Toplam bilinmiyorsa (kurulum) `nil`.
    var done: UInt64?
    var total: UInt64?

    var fraction: Double? {
        guard let done, let total, total > 0 else { return nil }
        return min(Double(done) / Double(total), 1)
    }
}

/// Birden çok dosyanın hep birlikte ilerleyişi.
///
/// Tek dosyanın çubuğu, on dosya gönderirken "kaçı bitti, ne kadar kaldı"
/// sorusunu cevaplamıyordu: her dosyada çubuk sıfırlanıyor ve toplam
/// görünmüyordu.
struct AndroidBatch: Equatable {
    /// Şu an sırada kaçıncı dosya (1'den başlayarak).
    var index: Int
    var count: Int
    /// Tamamlanmış dosyaların toplam baytı; süren dosya buna dahil değil.
    var completedBytes: UInt64
    var totalBytes: UInt64

    var isMultiple: Bool { count > 1 }

    /// Biten dosyalar + sürenin o anki durumu.
    func fraction(adding current: UInt64?) -> Double? {
        guard totalBytes > 0 else { return nil }
        return min(Double(completedBytes + (current ?? 0)) / Double(totalBytes), 1)
    }

    func doneBytes(adding current: UInt64?) -> UInt64 {
        completedBytes + (current ?? 0)
    }
}

enum AndroidFileError: LocalizedError {
    case adbMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .adbMissing: L10n.androidAdbMissing
        case .failed(let message): message
        }
    }
}

/// Telefonun dosya sistemine `adb` üzerinden erişir.
///
/// **Neden `adb`:** Telefon "Dosya aktarımı" modundayken macOS'un kendi
/// yolları (ImageCaptureCore) yalnızca fotoğrafları görüyor; Belgeler,
/// İndirilenler ve diğer klasörler için MTP'yi baştan yazmak ya da
/// `adb` kullanmak gerekiyor. `adb` bugün çalışıyor, MTP sonra gelecek
/// (bkz. plans).
///
/// **Sınır:** Sandbox başka bir programı çalıştırmayı yasaklıyor, yani bu
/// yol yalnızca doğrudan dağıtılan (Developer ID) sürümde çalışır; mağaza
/// sürümünde `adbMissing` yolu görünür. `adb`'yi uygulama paketine gömmek
/// ayrı bir adım — lisans nedeniyle kaynaktan derlenmesi gerekiyor.
struct AndroidFileService: Sendable {
    let serial: String

    /// `adb` nerede aranıyor: önce uygulamanın kendi paketi (ileride
    /// gömülecek), sonra Android SDK'nın standart yeri, sonra paket
    /// yöneticilerinin yolları. `PATH`'e güvenilmiyor — bir GUI
    /// uygulamasının `PATH`'i kabuğunkinden farklı ve genelde dar.
    static var adbURL: URL? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "adb") {
            candidates.append(bundled)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates += [
            home.appending(path: "Library/Android/sdk/platform-tools/adb"),
            URL(filePath: "/opt/homebrew/bin/adb"),
            URL(filePath: "/usr/local/bin/adb"),
            home.appending(path: "Android/sdk/platform-tools/adb"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isAvailable: Bool { adbURL != nil }

    // MARK: - Listeleme

    /// Verilen klasörün içeriği, klasörler önce.
    func list(path: String) async throws -> [AndroidFile] {
        // Sonda eğik çizgi şart: `/sdcard` gibi girdilerin çoğu bağlantı
        // ve eğik çizgisiz `ls` bağlantının içeriğini değil kendisini tek
        // satır olarak yazıyor — liste tek bir girdiyle boş görünüyordu.
        let target = path.hasSuffix("/") ? path : path + "/"
        let output = try await run(["shell", "ls", "-la", shellQuoted(target)])
        var files: [AndroidFile] = []

        for line in output.split(separator: "\n") {
            let raw = line.trimmingCharacters(in: .whitespaces)
            // `ls` başlıkta toplam blok sayısını yazıyor; girdi değil.
            guard !raw.isEmpty, !raw.hasPrefix("total ") else { continue }
            guard let file = Self.parse(line: raw, parent: path) else { continue }
            // "." ve ".." gezinmede işe yaramıyor: geri gitmeyi yol
            // çubuğu zaten sağlıyor.
            guard file.name != ".", file.name != ".." else { continue }
            files.append(file)
        }

        files.sort {
            $0.isOpenable == $1.isOpenable
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.isOpenable
        }
        return files
    }

    /// `ls -la` satırı: izinler, bağlantı sayısı, sahip, grup, boyut,
    /// tarih, saat, ad. Ad boşluk içerebildiği için yalnızca ilk yedi
    /// alan ayrılıyor, gerisi ad.
    private static func parse(line: String, parent: String) -> AndroidFile? {
        let parts = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
        guard parts.count == 8, let kind = parts[0].first else { return nil }

        var name = String(parts[7])
        var linkTarget: String?
        if kind == "l", let range = name.range(of: " -> ") {
            linkTarget = String(name[range.upperBound...])
            name = String(name[..<range.lowerBound])
        }
        guard !name.isEmpty else { return nil }

        let base = parent.hasSuffix("/") ? String(parent.dropLast()) : parent
        return AndroidFile(
            name: name,
            path: "\(base)/\(name)",
            isDirectory: kind == "d",
            linkTarget: linkTarget,
            size: UInt64(parts[4]) ?? 0,
            modified: "\(parts[5]) \(parts[6])"
        )
    }

    // MARK: - Aktarma

    /// Telefondan Mac'e.
    ///
    /// `adb` ilerleme yüzdesini yalnızca uçbirime yazıyor; çıktısı bir
    /// boruya gittiğinde hiçbir şey basmıyor. Bu yüzden ilerleme, hedef
    /// dosyanın büyümesi ölçülerek çıkarılıyor.
    func pull(
        _ file: AndroidFile, to destination: URL,
        onProgress: (@MainActor @Sendable (AndroidTransfer) -> Void)? = nil
    ) async throws {
        let watcher = onProgress.map { report in
            _Concurrency.Task {
                while !_Concurrency.Task.isCancelled {
                    try? await _Concurrency.Task.sleep(for: .milliseconds(300))
                    let done = (try? FileManager.default.attributesOfItem(
                        atPath: destination.path
                    )[.size] as? UInt64) ?? nil
                    let transfer = AndroidTransfer(name: file.name, done: done ?? 0, total: file.size)
                    await MainActor.run { report(transfer) }
                }
            }
        }
        defer { watcher?.cancel() }
        _ = try await run(["pull", "-a", file.path, destination.path])
    }

    /// Mac'ten telefona.
    func push(
        _ source: URL, to remoteDirectory: String,
        onProgress: (@MainActor @Sendable (AndroidTransfer) -> Void)? = nil
    ) async throws {
        let name = source.lastPathComponent
        let remote = remoteDirectory.hasSuffix("/")
            ? remoteDirectory + name
            : remoteDirectory + "/" + name
        try await push(source, toPath: remote, onProgress: onProgress)
    }

    /// Hedefi klasör değil, tam dosya yolu olarak alan biçim. Kurulum
    /// paketi cihazda geçici bir yola kopyalanırken buna ihtiyaç var.
    func push(
        _ source: URL, toPath remote: String,
        onProgress: (@MainActor @Sendable (AndroidTransfer) -> Void)? = nil
    ) async throws {
        let total = (try? FileManager.default.attributesOfItem(
            atPath: source.path
        )[.size] as? UInt64) ?? nil
        let name = source.lastPathComponent

        let watcher = onProgress.map { report in
            _Concurrency.Task {
                while !_Concurrency.Task.isCancelled {
                    try? await _Concurrency.Task.sleep(for: .milliseconds(500))
                    // Telefondaki dosyanın büyümesi: yerelde olduğu gibi
                    // doğrudan okunamıyor, cihaza sorulması gerekiyor.
                    let output = try? await run(["shell", "stat", "-c", "%s", shellQuoted(remote)])
                    let done = output.flatMap { UInt64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    let transfer = AndroidTransfer(name: name, done: done ?? 0, total: total)
                    await MainActor.run { report(transfer) }
                }
            }
        }
        defer { watcher?.cancel() }
        _ = try await run(["push", source.path, remote])
    }

    /// APK kurulumu. `-r` var olan uygulamanın üstüne yazıyor: aynı
    /// uygulamanın yeni sürümünü kurmak en sık kullanım.
    func install(
        apk: URL,
        onProgress: (@MainActor @Sendable (AndroidTransfer) -> Void)? = nil,
        onInstalling: (@MainActor @Sendable () -> Void)? = nil
    ) async throws {
        // `adb install` tek adımda hallediyor ama paketi cihazda kendi
        // seçtiği bir yere kopyaladığı için ilerleme ölçülemiyordu;
        // kullanıcı 60 MB'lık bir pakette ne kadar kaldığını göremiyordu.
        // Aynı iş iki adıma bölününce kopyalama ölçülebilir hâle geliyor.
        let remote = "/data/local/tmp/glassdo-\(UUID().uuidString).apk"

        try await push(apk, toPath: remote, onProgress: onProgress)
        // Kopya bitti; buradan sonrası cihazın işi ve süresi ölçülemiyor.
        if let onInstalling { await MainActor.run { onInstalling() } }

        defer {
            // Geçici kopya her durumda siliniyor: kurulum başarısız olsa
            // bile cihazda 60 MB'lık bir artık bırakmanın anlamı yok.
            _Concurrency.Task { _ = try? await run(["shell", "rm", "-f", shellQuoted(remote)]) }
        }

        let output = try await run(["shell", "pm", "install", "-r", shellQuoted(remote)])
        guard output.contains("Success") else {
            throw AndroidFileError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Bir dosyanın önizlemesi — resimde kendisi, videoda ilk kare.
    ///
    /// Telefonda küçük resim üretmenin yolu yok; dosya geçici bir klasöre
    /// çekilip burada işleniyor ve kopya hemen siliniyor. Video için
    /// sınır daha dar tutuluyor: bir ekran kaydı yüzlerce megabayt
    /// olabiliyor ve sırf kapak için onu çekmek telefonu da kabloyu da
    /// boşuna yorar.
    func thumbnail(for file: AndroidFile, maxPixel: CGFloat = 320) async throws -> NSImage? {
        let limit: UInt64 = file.isVideo ? 400 * 1024 * 1024 : 25 * 1024 * 1024
        guard file.isImage || file.isVideo, file.size <= limit else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GlassDoAndroidPreview", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let local = directory.appending(path: UUID().uuidString + "-" + file.name)
        defer { try? FileManager.default.removeItem(at: local) }

        _ = try await run(["pull", "-a", file.path, local.path])

        let image: NSImage?
        if file.isVideo {
            image = Self.videoFrame(at: local, maxPixel: maxPixel)
        } else {
            image = NSImage(contentsOf: local)
        }
        guard let image else { return nil }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxPixel / max(size.width, size.height), 1)
        guard scale < 1 else { return image }

        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target))
        resized.unlockFocus()
        return resized
    }

    /// Videonun kapak karesi. Baştan tam sıfırıncı saniye çoğu kayıtta
    /// siyah; biraz ileriden alınıyor.
    private static func videoFrame(at url: URL, maxPixel: CGFloat) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel * 2, height: maxPixel * 2)
        // Kareyi tam isteneni bulmak için aramak yavaş; yakını yeterli.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            // Bir saniyelik video olabilir: en baştan dene.
            guard let first = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
            return NSImage(cgImage: first, size: .zero)
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    /// Telefondaki dosyayı ya da klasörü siler.
    func delete(_ file: AndroidFile) async throws {
        _ = try await run(["shell", "rm", file.isOpenable ? "-rf" : "-f", shellQuoted(file.path)])
    }

    /// Telefonun depolama durumu.
    ///
    /// `df -h` yerine ham `df`: okunur birimler cihazdan cihaza farklı
    /// yazılıyor ("60G", "60Gi") ve arayüzün geri kalanıyla aynı biçimde
    /// göstermek için sayının kendisi gerekiyor. Değerler 1K blok.
    func storage(path: String = "/sdcard") async throws -> AndroidStorage? {
        let output = try await run(["shell", "df", shellQuoted(path)])
        let lines = output.split(separator: "\n")
        guard lines.count > 1 else { return nil }

        let fields = lines[1].split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count > 3,
              let total = UInt64(fields[1]), let used = UInt64(fields[2]),
              let free = UInt64(fields[3])
        else { return nil }

        let block: UInt64 = 1024
        return AndroidStorage(total: total * block, used: used * block, free: free * block)
    }

    // MARK: - Komut çalıştırma

    /// Kabuk argümanı olarak güvenli hâle getiriyor: `adb shell` komutu
    /// telefonda bir kabuktan geçiyor, boşluklu ve tırnaklı adlar aksi
    /// hâlde bölünürdü.
    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func run(_ arguments: [String]) async throws -> String {
        guard let adb = Self.adbURL else { throw AndroidFileError.adbMissing }
        let serial = serial

        return try await withCheckedThrowingContinuation { continuation in
            // Süreç çalıştırmak bloklayıcı: ana aktörden uzak tutuluyor,
            // yoksa büyük bir klasörde arayüz donardı.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = adb
                process.arguments = ["-s", serial] + arguments

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: AndroidFileError.failed(error.localizedDescription))
                    return
                }

                // Okuma bitmeden `waitUntilExit` çağrılırsa büyük çıktıda
                // boru dolup süreç kilitlenir.
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(decoding: outData, as: UTF8.self)
                let errorText = String(decoding: errData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus != 0 {
                    continuation.resume(
                        throwing: AndroidFileError.failed(errorText.isEmpty ? output : errorText)
                    )
                } else {
                    continuation.resume(returning: output)
                }
            }
        }
    }
}
