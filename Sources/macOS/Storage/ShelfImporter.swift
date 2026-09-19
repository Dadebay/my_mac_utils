import AppKit
import Foundation
import UniformTypeIdentifiers

/// Rafa dosya/görsel almanın tek yeri.
///
/// İki ayrı yerden çağrılıyor: açık raf panelinin kendisi ve dar raydaki
/// raf ikonu (panel kapalıyken sürüklenen görsel doğrudan oraya
/// bırakılabilsin diye). Mantık kopyalansaydı iki giriş noktası zamanla
/// birbirinden ayrılırdı — biri ham görseli kabul ederken öteki etmezdi.
@MainActor
enum ShelfImporter {

    /// Sürüklenen sağlayıcıları çözüp rafa yazar. Hiçbir şey çözülemezse
    /// `false` döner; çağıran buna göre geri bildirim verebilir.
    @discardableResult
    static func importDropped(_ providers: [NSItemProvider]) async throws -> Bool {
        var urls: [URL] = []
        var rawItems: [(data: Data, name: String, type: UTType)] = []

        for provider in providers {
            // `loadFileURL()`, `NSURL`'in genel `NSItemProviderReading`
            // uyumu yüzünden web sayfasındaki bir görselin uzak (http://…)
            // adresini de döndürebiliyor — bu yerel dosya sanılıp diskte
            // "bulunamadı" hatasına yol açardı. Yalnızca gerçek dosya
            // URL'leri kopyalama yoluna giriyor.
            if let url = await provider.loadFileURL(), url.isFileURL {
                // Klasörler rafa girmiyor: raf tek tek dosyalar için.
                guard !url.hasDirectoryPath else { continue }
                urls.append(url)
                continue
            }
            if let raw = await provider.loadRawMedia() {
                rawItems.append(raw)
            }
        }

        guard !urls.isEmpty || !rawItems.isEmpty else { return false }

        let service = try ManagedStorageService.default()
        let shelf = try service.prepareShelf()
        for url in urls {
            try service.importFile(at: url, into: shelf)
        }
        for raw in rawItems {
            try service.importData(raw.data, suggestedName: raw.name, type: raw.type, into: shelf)
        }
        return true
    }

    /// Sürükleme sırasında panelin/rayın kabul edeceği türler.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .movie]
}

// MARK: - Sürükleme çözümleme

@MainActor
extension NSItemProvider {
    /// `NSItemProvider`'ın geri çağırmalı API'sini bekleyebilir hâle getirir.
    func loadFileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    /// Bir web sayfasından ya da başka bir uygulamadan doğrudan sürüklenen
    /// görsel/video verisini yükler. `loadFileURL()` yalnızca Finder'daki
    /// dosyaları kapsıyor; buradaki içerik disk üzerinde yok, yalnızca
    /// sağlayıcının bellekteki temsili.
    func loadRawMedia() async -> (data: Data, name: String, type: UTType)? {
        // Önce genel görsel yükleme: kaynağın kaydettiği tam UTI'yi bilmeye
        // gerek kalmadan neredeyse her temsili kapsıyor — `NSImage`,
        // `NSItemProviderReading`'e uyduğu için web sayfası, Önizleme,
        // Mesajlar, Fotoğraflar gibi çok farklı kaynaklardan gelen görseli
        // aynı yoldan çözüyor.
        if hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let image: NSImage? = await withCheckedContinuation { continuation in
                _ = loadObject(ofClass: NSImage.self) { image, _ in
                    continuation.resume(returning: image as? NSImage)
                }
            }
            if let image, let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                return (png, suggestedName ?? "Image", .png)
            }
        }

        // Video ve genel yüklemenin çözemediği ender türler için ham veri.
        let candidates: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie, .png, .jpeg, .tiff, .heic, .gif]
        guard let type = candidates.first(where: { hasItemConformingToTypeIdentifier($0.identifier) })
        else { return nil }

        let data: Data? = await withCheckedContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }

        let name = suggestedName ?? (type.conforms(to: .movie) ? "Video" : "Image")
        return (data, name, type)
    }
}
