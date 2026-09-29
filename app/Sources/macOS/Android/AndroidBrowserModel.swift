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

    func load(path newPath: String? = nil) {
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

        _Concurrency.Task { @MainActor in
            do {
                try await service.pull(file, to: destination.appending(path: file.name))
                NSWorkspace.shared.activateFileViewerSelecting([destination.appending(path: file.name)])
            } catch {
                errorMessage = error.localizedDescription
            }
            busyMessage = nil
        }
    }

    /// Mac'ten sürüklenen ya da seçilen dosyaları bulunulan klasöre yükler.
    func upload(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        busyMessage = urls.count == 1
            ? L10n.androidUploading(urls[0].lastPathComponent)
            : L10n.androidUploadingCount(urls.count)

        _Concurrency.Task { @MainActor in
            do {
                for url in urls {
                    // APK'ler yüklenmek yerine kuruluyor: telefona kopyalanan
                    // bir APK kendiliğinden kurulmuyor, kullanıcı da bunu
                    // bekliyor.
                    if url.pathExtension.lowercased() == "apk" {
                        try await service.install(apk: url)
                    } else {
                        try await service.push(url, to: path)
                    }
                }
                load()
            } catch {
                errorMessage = error.localizedDescription
            }
            busyMessage = nil
        }
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
