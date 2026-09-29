import AppKit
import CryptoKit

/// Pencere küçük resimlerinin diskteki deposu.
///
/// Küçültülmüş bir pencere ekranda çizilmediği için yakalanamıyor; tek
/// kaynak, küçültülmeden önce alınmış son görüntü. O görüntü yalnızca
/// bellekte tutulurken uygulama her yeniden başladığında kayboluyordu ve
/// değiştirici küçültülmüş pencereleri boş bir kartla gösteriyordu
/// (kullanıcı bildirdi). Disk deposu bu boşluğu kapatıyor.
///
/// Görüntüler uygulamanın kendi Application Support klasöründe duruyor —
/// mağaza sürümünde bu klasör sandbox kabının içinde, başka uygulamalar
/// okuyamıyor.
enum SwitcherThumbnailStore {
    /// Diske yazarken küçültme sınırı. Kart en fazla ~320 pt genişliğinde
    /// çiziliyor; Retina için iki katı fazlasıyla yetiyor ve dosyaları
    /// yüz kilobayt yerine birkaç kilobayt tutuyor.
    private static let maxWidth: CGFloat = 640
    /// Diskte tutulan en fazla görüntü. Aşınca en eskiler siliniyor.
    private static let maxFiles = 80

    private static let directory: URL? = {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let url = base
            .appendingPathComponent("GlassDo", isDirectory: true)
            .appendingPathComponent("SwitcherThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Dosya adı anahtarın özetinden: pencere başlıkları eğik çizgi ve
    /// iki nokta içerebiliyor, ham hâlleri dosya adı olmuyor.
    private static func fileURL(for key: String) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).jpg")
    }

    // MARK: - Okuma

    /// Diskteki bütün görüntüler, anahtarlarıyla. Anahtar dosya adından
    /// geri üretilemediği için yanına küçük bir dizin dosyası yazılıyor.
    static func loadAll() -> [String: NSImage] {
        guard let directory,
              let indexData = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
              let index = try? JSONDecoder().decode([String: String].self, from: indexData)
        else { return [:] }

        var result: [String: NSImage] = [:]
        for (key, file) in index {
            let url = directory.appendingPathComponent(file)
            guard let image = NSImage(contentsOf: url) else { continue }
            result[key] = image
        }
        return result
    }

    // MARK: - Yazma

    /// Görüntüyü küçültüp diske yazar ve dizini günceller. Yazma çağıranı
    /// bekletmesin diye arka planda.
    static func store(_ image: NSImage, for key: String) {
        guard let directory, let url = fileURL(for: key) else { return }
        let fileName = url.lastPathComponent

        // `NSImage` ana aktöre bağlı değil; çizim arka planda güvenli.
        let source = image
        DispatchQueue.global(qos: .utility).async {
            guard let data = jpegData(from: source) else { return }
            try? data.write(to: url, options: .atomic)

            var index = (try? Data(contentsOf: directory.appendingPathComponent("index.json")))
                .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            index[key] = fileName
            if let encoded = try? JSONEncoder().encode(index) {
                try? encoded.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
            }
            prune(directory: directory)
        }
    }

    private static func jpegData(from image: NSImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = min(maxWidth / size.width, 1)
        let target = NSSize(width: size.width * scale, height: size.height * scale)

        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    /// En eski dosyaları atarak depoyu sınırda tutuyor.
    private static func prune(directory: URL) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter({ $0.pathExtension == "jpg" }), files.count > maxFiles else { return }

        let sorted = files.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        for url in sorted.prefix(files.count - maxFiles) {
            try? manager.removeItem(at: url)
        }
    }
}
