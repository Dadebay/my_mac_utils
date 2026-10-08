import AppKit
import Foundation
import GlassDoKit

/// Telefon dosya gezgininin durumu: hangi klasördeyiz, içinde ne var,
/// hangi iş sürüyor.
@MainActor
@Observable
final class AndroidBrowserModel {
    /// Gezinme burada başlıyor: kullanıcının kendi dosyaları `/sdcard`
    /// altında. Kök dizin (`/`) sistem klasörleriyle dolu ve çoğu
    /// okunamıyor — ilk ekranda boş bir liste gibi görünürdü.
    static let rootPath = "/sdcard"

    private(set) var files: [AndroidFile] = []
    private(set) var path = rootPath
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var storage: AndroidStorage?
    /// Süren aktarma varsa açıklaması — düğmeler bu sırada kilitleniyor.
    private(set) var busyMessage: String?
    /// Süren aktarmanın baytları — kaç MB'ın geçtiği buradan okunuyor.
    private(set) var transfer: AndroidTransfer?
    /// Birden çok dosya gönderilirken toplam durum: kaçıncı dosyadayız ve
    /// hepsinin kaç baytı geçti.
    private(set) var batch: AndroidBatch?
    /// Biten işin tek satırlık sonucu ("… kuruldu", "… gönderildi").
    /// Kurulan bir APK telefonda dosya olarak görünmüyor; sessiz kalınca
    /// kullanıcı hiçbir şey olmadı sanıyordu.
    private(set) var statusMessage: String?

    func dismissStatus() { statusMessage = nil }

    /// Çekilmiş önizlemeler, yol başına. Klasör değişince boşalıyor:
    /// başka klasördeki resimleri bellekte tutmanın karşılığı yok.
    private(set) var thumbnails: [String: NSImage] = [:]
    private var pendingThumbnails: Set<String> = []

    private let service: AndroidFileService

    init(serial: String) {
        service = AndroidFileService(serial: serial)
    }

    /// Yol çubuğunun parçaları: görünen ad ve o ada tıklanınca gidilecek yol.
    var breadcrumbs: [(name: String, path: String)] {
        var result: [(String, String)] = []
        var current = ""
        for component in path.split(separator: "/") {
            current += "/\(component)"
            result.append((String(component), current))
        }
        return result
    }

    var canGoUp: Bool { path != "/" }

    /// Izgara görünümünde resimlerin önizlemesi isteniyor. Aynı dosya için
    /// ikinci kez çekim başlatılmıyor.
    func requestThumbnail(for file: AndroidFile) {
        guard file.isImage, thumbnails[file.path] == nil, !pendingThumbnails.contains(file.path)
        else { return }
        pendingThumbnails.insert(file.path)

        _Concurrency.Task { @MainActor in
            let image = try? await service.thumbnail(for: file)
            pendingThumbnails.remove(file.path)
            // Kullanıcı bu arada başka klasöre geçtiyse görüntüyü ekleme.
            guard file.path.hasPrefix(path) else { return }
            if let image { thumbnails[file.path] = image }
        }
    }

    func load(path newPath: String? = nil) {
        if let newPath, newPath != path {
            thumbnails = [:]
            pendingThumbnails = []
        }
        if let newPath { path = newPath }
        isLoading = true
        errorMessage = nil

        _Concurrency.Task { @MainActor in
            do {
                files = try await service.list(path: path)
                storage = try? await service.storage(path: path)
            } catch {
                files = []
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func open(_ file: AndroidFile) {
        guard file.isOpenable else { return }
        // Bağlantının hedefi mutlak yolsa oraya gidiliyor: `/sdcard` gibi
        // girdiler zaten başka bir yere işaret ediyor ve bağlantının kendi
        // yolundan listelemek bazı cihazlarda boş dönüyor.
        let target = file.linkTarget.map { $0.hasPrefix("/") ? $0 : file.path } ?? file.path
        load(path: target)
    }

    func goUp() {
        guard canGoUp else { return }
        let parent = (path as NSString).deletingLastPathComponent
        load(path: parent.isEmpty ? "/" : parent)
    }

    // MARK: - Aktarma

    /// Seçilen dosyayı Mac'e indirir; nereye kaydedileceğini kullanıcı
    /// seçiyor.
    func download(_ file: AndroidFile) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.androidSaveHere
        panel.message = L10n.androidChooseDestination(file.name)

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busyMessage = L10n.androidDownloading(file.name)
        statusMessage = nil
        transfer = AndroidTransfer(name: file.name, done: 0, total: file.size)

        _Concurrency.Task { @MainActor in
            let target = destination.appending(path: file.name)
            do {
                try await service.pull(file, to: target) { [weak self] progress in
                    self?.transfer = progress
                }
                statusMessage = L10n.androidSavedTo(file.name, destination.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } catch {
                errorMessage = error.localizedDescription
            }
            busyMessage = nil
            transfer = nil
        }
    }

    /// Sürükleyip bırakmak için: dosyayı geçici bir klasöre indirir ve
    /// yerel kopyanın yolunu döndürür. Finder'a bırakılan öğe bu kopya.
    func stageForDrag(_ file: AndroidFile) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GlassDoAndroidDrag/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: file.name)

        await MainActor.run {
            busyMessage = L10n.androidDownloading(file.name)
            transfer = AndroidTransfer(name: file.name, done: 0, total: file.size)
        }
        defer {
            _Concurrency.Task { @MainActor in
                busyMessage = nil
                transfer = nil
            }
        }

        try await service.pull(file, to: target) { [weak self] progress in
            self?.transfer = progress
        }
        return target
    }

    /// Mac'ten sürüklenen ya da seçilen dosyaları bulunulan klasöre yükler.
    func upload(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        statusMessage = nil

        // Toplam boyut baştan biliniyor: tek dosyanın çubuğu on dosyalık
        // bir gönderimde "ne kadar kaldı" sorusunu cevaplamıyor.
        let sizes = urls.map { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? nil
        }
        batch = AndroidBatch(
            index: 1, count: urls.count,
            completedBytes: 0,
            totalBytes: sizes.compactMap { $0 }.reduce(0, +)
        )

        _Concurrency.Task { @MainActor in
            var installed: [String] = []
            var copied: [String] = []
            do {
                for (offset, url) in urls.enumerated() {
                    batch?.index = offset + 1
                    let size = sizes[offset] ?? nil

                    // APK'ler yüklenmek yerine kuruluyor: telefona kopyalanan
                    // bir APK kendiliğinden kurulmuyor, kullanıcı da bunu
                    // bekliyor. Kurulan paket klasörde görünmediği için
                    // sonucu ayrıca söylemek gerekiyor.
                    if url.pathExtension.lowercased() == "apk" {
                        // Kurulum iki aşamalı: önce paket telefona
                        // kopyalanıyor (ölçülebiliyor), sonra cihaz onu
                        // kuruyor (süresi ölçülemiyor).
                        busyMessage = L10n.androidCopyingToPhone(url.lastPathComponent)
                        transfer = AndroidTransfer(name: url.lastPathComponent, done: 0, total: size)
                        try await service.install(
                            apk: url,
                            onProgress: { [weak self] progress in self?.transfer = progress },
                            onInstalling: { [weak self] in
                                self?.busyMessage = L10n.androidInstalling(url.lastPathComponent)
                                self?.transfer = nil
                            }
                        )
                        installed.append(url.lastPathComponent)
                    } else {
                        busyMessage = L10n.androidUploading(url.lastPathComponent)
                        transfer = AndroidTransfer(name: url.lastPathComponent, done: 0, total: size)
                        try await service.push(url, to: path) { [weak self] progress in
                            self?.transfer = progress
                        }
                        copied.append(url.lastPathComponent)
                    }

                    // Biten dosya toplama ekleniyor; sıradakinin çubuğu
                    // sıfırdan değil, kalınan yerden devam ediyor.
                    batch?.completedBytes += size ?? 0
                    transfer = nil
                }
                load()
                statusMessage = Self.summary(installed: installed, copied: copied)
            } catch {
                errorMessage = error.localizedDescription
            }
            busyMessage = nil
            transfer = nil
            batch = nil
        }
    }

    private static func summary(installed: [String], copied: [String]) -> String? {
        if !installed.isEmpty, copied.isEmpty {
            return installed.count == 1
                ? L10n.androidInstalled(installed[0])
                : L10n.androidInstalledCount(installed.count)
        }
        if installed.isEmpty, !copied.isEmpty {
            return copied.count == 1
                ? L10n.androidCopiedOne(copied[0])
                : L10n.androidCopiedCount(copied.count)
        }
        guard !installed.isEmpty else { return nil }
        return L10n.androidMixedResult(copied.count, installed.count)
    }

    func chooseFilesToUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.androidSend
        guard panel.runModal() == .OK else { return }
        upload(panel.urls)
    }

    func dismissError() { errorMessage = nil }
}
