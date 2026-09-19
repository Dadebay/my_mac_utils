import AppKit
import Darwin
import Foundation
import GlassDoKit

extension Notification.Name {
    /// Raf içeriği uygulama içi bir eylem dışında (ör. otomatik ekran
    /// görüntüsü aktarımı) değiştiğinde yayınlanır — açık `PanelShelfView`
    /// bunu dinleyip yeniden yüklüyor.
    static let glassDoShelfContentsChanged = Notification.Name("GlassDoShelfContentsChanged")
}

/// Sistemin ekran görüntüsü klasörünü izler, yeni bir görüntü çekilince
/// onu Rafa **taşır** (kopyalamaz) — amaç Masaüstü'nü biriken ekran
/// görüntülerinden kurtarmak, orada bir kopyasını daha bırakmak değil.
///
/// **Neden `NSMetadataQuery` değil:** ilk sürüm Spotlight sorgusu
/// kullanıyordu ve ekran görüntüleri Masaüstü'nde kalıyordu — o sorgu
/// dosyanın dizinlenmesini bekliyor, dizinleme gecikmeli ve canlı
/// güncelleme bildirimleri güvenilir biçimde gelmiyor. Oysa
/// `screencapture` aracı `kMDItemIsScreenCapture` işaretini **doğrudan
/// dosyanın genişletilmiş özniteliğine** yazıyor: klasörü kendimiz izleyip
/// bu özniteliği okumak hem anında hem de Spotlight'tan bağımsız.
///
/// Dosya adına bakmak bir seçenek değildi: ad dile bağlı (İngilizce
/// sistemde "Screenshot …", Türkçe'de başka) ve kullanıcı tarafından
/// değiştirilebilir.
@MainActor
final class ScreenshotShelfWatcher {
    static let shared = ScreenshotShelfWatcher()

    /// `screencapture`'ın dosyaya kendi koyduğu işaret.
    private static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

    /// Dosya klasörde belirdiği anda öznitelik henüz yazılmamış olabiliyor;
    /// bu süre boyunca kısa aralıklarla tekrar bakılıyor. Sonunda hâlâ yoksa
    /// dosya ekran görüntüsü değildir ve ona hiç dokunulmuyor.
    private static let attributeWaitAttempts = 12
    private static let attributeRetryDelay: Duration = .milliseconds(180)

    /// Tek bir ekran görüntüsü klasörde birkaç ayrı olay üretebiliyor;
    /// tarama bu kadar sessizlikten sonra bir kez yapılıyor.
    private static let scanDebounce: Duration = .milliseconds(350)

    private var source: DispatchSourceFileSystemObject?
    private var watchedDirectory: URL?
    /// Hakkında karar verilmiş dosyalar. İzleme başladığında klasörde zaten
    /// duranlar da buraya giriyor: özellik açıldığında Masaüstü'nü toplu
    /// hâlde boşaltmak kullanıcının beklemediği bir "temizlik" olurdu.
    private var knownFiles: Set<URL> = []
    private var pendingScan: _Concurrency.Task<Void, Never>?
    /// Bir tarama şu an `waitForScreenCaptureAttribute` içinde bekliyor mu.
    /// Bu sırada gelen yeni bir olay taramayı iptal etmemeli — aksi hâlde
    /// art arda çekilen iki ekran görüntüsünde ilki hep bir adım geriden
    /// gelirdi (bkz. `scheduleScan`).
    private var isScanning = false
    private var rescanNeededAfterCurrentScan = false

    private init() {}

    /// Ayardaki anahtarla senkron tutar — açılışta ve ayar her
    /// değiştiğinde çağrılması yeterli.
    func syncWithSetting() {
        if PanelSettings.autoAddScreenshotsToShelf {
            start()
        } else {
            stop()
        }
    }

    // MARK: - İzleme

    private func start() {
        let directory = screenshotDirectory
        // Kullanıcı kayıt yerini değiştirmiş olabilir; aynı klasördeysek
        // çalışan izleyiciyi boşuna yeniden kurmuyoruz.
        if source != nil, watchedDirectory == directory { return }
        stop()

        let descriptor = directory.withUnsafeFileSystemRepresentation { path -> CInt in
            guard let path else { return -1 }
            return open(path, O_EVTONLY)
        }
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let events = source.data
                // Klasörün kendisi taşınmış/silinmişse tanıtıcı artık geçersiz;
                // yeni yola baştan bağlanmak gerekiyor.
                if events.contains(.delete) || events.contains(.rename) {
                    self.stop()
                    self.syncWithSetting()
                } else {
                    self.scheduleScan()
                }
            }
        }
        source.setCancelHandler { close(descriptor) }

        watchedDirectory = directory
        knownFiles = Set(directoryContents(of: directory))
        self.source = source
        source.resume()
    }

    private func stop() {
        pendingScan?.cancel()
        pendingScan = nil
        rescanNeededAfterCurrentScan = false
        source?.cancel()
        source = nil
        watchedDirectory = nil
        knownFiles = []
    }

    private func scheduleScan() {
        // Bir tarama zaten `waitForScreenCaptureAttribute` içinde
        // bekliyorsa onu iptal edip yeniden başlatmak, tam da o dosyanın
        // özniteliğini bekleyen döngüyü yarıda kesip kaybettiriyordu — dosya
        // zaten `knownFiles`'a işlenmiş sayıldığı için bir daha hiç
        // denenmiyordu, ta ki bir SONRAKİ ekran görüntüsünün olayı bu
        // fonksiyonu tekrar tetikleyip taramayı "kazayla" tamamlatana kadar.
        // O yüzden aktif bir tarama sürerken yeni olay onu iptal etmiyor,
        // yalnızca bitince bir kez daha taransın diye işaretliyor.
        guard !isScanning else {
            rescanNeededAfterCurrentScan = true
            return
        }

        pendingScan?.cancel()
        pendingScan = _Concurrency.Task { @MainActor [weak self] in
            try? await _Concurrency.Task.sleep(for: Self.scanDebounce)
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.runScan()
        }
    }

    private func runScan() async {
        isScanning = true
        await scanForNewScreenshots()
        isScanning = false

        if rescanNeededAfterCurrentScan {
            rescanNeededAfterCurrentScan = false
            scheduleScan()
        }
    }

    // MARK: - Tarama

    private func scanForNewScreenshots() async {
        guard let directory = watchedDirectory else { return }
        let contents = directoryContents(of: directory)

        // Silinen/taşınan dosyaları unut — küme klasörle birlikte küçülsün.
        knownFiles.formIntersection(contents)

        let candidates = contents.filter { !knownFiles.contains($0) }
        guard !candidates.isEmpty else { return }
        // Her aday bir kez değerlendiriliyor: aşağıdaki bekleme sırasında
        // klasöre yeni olaylar düşse bile aynı dosya iki kez taşınmasın.
        knownFiles.formUnion(candidates)

        var screenshots: [URL] = []
        for url in candidates where await Self.waitForScreenCaptureAttribute(url) {
            screenshots.append(url)
        }
        guard !screenshots.isEmpty else { return }

        moveToShelf(screenshots)
    }

    private func directoryContents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
    }

    /// Dosya klasörde belirdiği anda öznitelik henüz yerinde olmayabiliyor;
    /// kısa bir süre bekleyip tekrar bakıyor.
    private static func waitForScreenCaptureAttribute(_ url: URL) async -> Bool {
        for attempt in 0..<attributeWaitAttempts {
            if hasScreenCaptureAttribute(url) { return true }
            // Dosya bu arada yok olduysa (ör. kullanıcı taşıdı) beklemeye
            // devam etmenin anlamı yok.
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            if attempt < attributeWaitAttempts - 1 {
                try? await _Concurrency.Task.sleep(for: attributeRetryDelay)
            }
        }
        return false
    }

    private static func hasScreenCaptureAttribute(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return getxattr(path, screenCaptureAttribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }

    // MARK: - Taşıma

    private func moveToShelf(_ urls: [URL]) {
        guard let service = try? ManagedStorageService.default() else { return }
        _Concurrency.Task.detached(priority: .utility) {
            guard let shelf = try? service.prepareShelf() else { return }
            var movedAny = false
            for url in urls where (try? service.moveFile(at: url, into: shelf)) != nil {
                movedAny = true
            }
            guard movedAny else { return }
            await MainActor.run {
                NotificationCenter.default.post(name: .glassDoShelfContentsChanged, object: nil)
            }
        }
    }

    // MARK: - Kayıt yeri

    /// `screencapture`'ın kayıt yeri — kullanıcı Shift+Cmd+5 ya da
    /// `defaults write com.apple.screencapture location` ile değiştirmiş
    /// olabilir; ayarlanmamışsa varsayılan Masaüstü.
    private var screenshotDirectory: URL {
        if let raw = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !raw.isEmpty {
            return URL(
                fileURLWithPath: (raw as NSString).expandingTildeInPath,
                isDirectory: true
            ).standardizedFileURL
        }
        return (FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
    }
}
