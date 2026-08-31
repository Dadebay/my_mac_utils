import AppKit
import Foundation
import GlassDoKit
import UniformTypeIdentifiers

/// Yönetilen alandaki bir dosyanın türü. Simge seçimi buradan geliyor —
/// uzantıya bakan `switch`'ler görünümlere dağılırsa zamanla ayrışırlar.
enum StorageItemKind: String, Sendable {
    case image, audio, video, pdf, archive, file

    var symbolName: String {
        switch self {
        case .image: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .pdf: "doc.richtext"
        case .archive: "archivebox"
        case .file: "doc"
        }
    }

    /// Türün kullanıcıya gösterilen adı sistemden geliyor ("JPEG görüntüsü");
    /// burada yalnızca hiç okunamadığında kullanılacak karşılık var.
    static func kind(for type: UTType?) -> StorageItemKind {
        guard let type else { return .file }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archive }
        return .file
    }
}

/// Yönetilen klasörün içindeki tek bir öğe.
struct StorageItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let size: UInt64
    let modifiedAt: Date
    let kind: StorageItemKind
    let isDirectory: Bool
    /// Sistemden okunan tür adı ("PNG görüntüsü"); okunamazsa boş.
    let typeDescription: String

    var id: URL { url }
}

/// GlassDo'nun kendi dosya alanı.
///
/// Kullanıcının Finder'da bağladığı klasörlerden ayrı bir yer: burada
/// oluşturulan her şeyi uygulama oluşturdu, dolayısıyla silme ve taşıma
/// sorumluluğu da uygulamanın. Dışarıdaki dosyalara bu servis üzerinden
/// **hiçbir yıkıcı işlem** yapılamıyor — her yıkıcı çağrı önce hedefin
/// kök dizinin içinde olduğunu doğruluyor.
///
/// Durum taşımıyor ve kökü dışarıdan alıyor: testler gerçek Application
/// Support yerine geçici bir dizin verebilsin diye.
struct ManagedStorageService: Sendable {

    enum StorageError: LocalizedError, Equatable {
        case storageUnavailable
        case invalidFolderName
        case folderCreationFailed(String)
        case copyFailed(name: String, reason: String)
        case outsideStorage
        /// İlk sürüm klasör içe aktarmıyor; sessizce yutmak yerine
        /// açıkça söylüyor.
        case directoriesNotSupported

        var errorDescription: String? {
            switch self {
            case .storageUnavailable:
                L10n.storageUnavailable
            case .invalidFolderName:
                L10n.storageInvalidFolderName
            case .folderCreationFailed:
                L10n.storageFolderCreationFailed
            case .copyFailed(let name, _):
                L10n.storageCopyFailed(name)
            case .outsideStorage:
                L10n.storageOutsideStorage
            case .directoriesNotSupported:
                L10n.storageDirectoriesNotSupported
            }
        }
    }

    /// Yönetilen alanın kökü. Uygulamada
    /// `~/Library/Application Support/GlassDo/Storage`, testlerde geçici dizin.
    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// Uygulamanın gerçek alanı. Ağ geçmişiyle aynı `GlassDo` klasörünün
    /// altında duruyor — uygulamanın diskteki her şeyi tek yerde.
    static func applicationSupportRoot() throws -> URL {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StorageError.storageUnavailable
        }
        return base
            .appendingPathComponent("GlassDo", isDirectory: true)
            .appendingPathComponent("Storage", isDirectory: true)
    }

    static func `default`() throws -> ManagedStorageService {
        ManagedStorageService(root: try applicationSupportRoot())
    }

    // MARK: - Kök

    @discardableResult
    func prepareRoot() throws -> URL {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw StorageError.storageUnavailable
        }
        return root
    }

    // MARK: - Klasör

    /// Klasör adını doğrular ve kırpar.
    ///
    /// Ad diskte bir yol bileşeni olarak kullanılmıyor (dizin adı UUID),
    /// ama yine de doğrulanıyor: kullanıcı "/" ya da yalnızca boşluk
    /// yazdığında listede adsız bir satır belirmesin.
    static func sanitized(folderName raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed.count <= 255 else {
            throw StorageError.invalidFolderName
        }
        // "." ve ".." dosya sisteminde yol anlamı taşır; yalnızca noktadan
        // oluşan her ad reddediliyor.
        guard !trimmed.allSatisfy({ $0 == "." }) else {
            throw StorageError.invalidFolderName
        }
        guard !trimmed.contains("/"), !trimmed.contains(":"), !trimmed.contains("\0") else {
            throw StorageError.invalidFolderName
        }
        guard trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw StorageError.invalidFolderName
        }

        return trimmed
    }

    /// Yeni klasör oluşturur ve diskteki gerçek dizinini döndürür.
    ///
    /// Dizin adı UUID: kullanıcı iki klasöre aynı adı verebilsin, ad
    /// değiştirmek diskte hiçbir şeyi taşımasın, klasör adı da dosya
    /// sistemi kurallarına esir olmasın.
    func createFolder(named rawName: String) throws -> (name: String, url: URL) {
        let name = try Self.sanitized(folderName: rawName)
        try prepareRoot()

        let url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            throw StorageError.folderCreationFailed(error.localizedDescription)
        }
        return (name, url)
    }

    // MARK: - Dosya alma

    /// Kaynak dosyayı yönetilen klasöre **kopyalar**. Kaynağa dokunulmuyor:
    /// kullanıcının Finder'daki dosyası yerinde kalıyor.
    @discardableResult
    func importFile(at source: URL, into directory: URL) throws -> URL {
        guard isInsideStorage(directory) else { throw StorageError.outsideStorage }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw StorageError.copyFailed(
                name: source.lastPathComponent,
                reason: "kaynak bulunamadı"
            )
        }
        guard !isDirectory.boolValue else {
            throw StorageError.directoriesNotSupported
        }

        let destination = uniqueDestination(for: source.lastPathComponent, in: directory)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw StorageError.copyFailed(
                name: source.lastPathComponent,
                reason: error.localizedDescription
            )
        }
        return destination
    }

    /// Çakışan adı "Photo 2.jpg", "Photo 3.jpg" diye açar. Üzerine yazmak
    /// kullanıcının başka bir dosyasını sessizce yok etmek olurdu.
    func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        var candidate = directory.appendingPathComponent(fileName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }

    // MARK: - Listeleme

    /// Klasörün içeriği, ada göre (Finder'ın kullandığı doğal sıralamayla).
    func contents(of directory: URL) throws -> [StorageItem] {
        guard isInsideStorage(directory) else { throw StorageError.outsideStorage }

        let keys: [URLResourceKey] = [
            .fileSizeKey, .contentModificationDateKey, .isDirectoryKey,
            .contentTypeKey, .localizedTypeDescriptionKey,
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        return urls
            .map(item(at:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func item(at url: URL) -> StorageItem {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .isDirectoryKey,
            .contentTypeKey, .localizedTypeDescriptionKey,
        ])

        let isDirectory = values?.isDirectory ?? false
        return StorageItem(
            url: url,
            name: url.lastPathComponent,
            size: UInt64(max(values?.fileSize ?? 0, 0)),
            modifiedAt: values?.contentModificationDate ?? .distantPast,
            kind: isDirectory ? .file : StorageItemKind.kind(for: values?.contentType),
            isDirectory: isDirectory,
            typeDescription: values?.localizedTypeDescription ?? ""
        )
    }

    /// Klasördeki dosya sayısı ve toplam boyut — liste satırı için.
    func summary(of directory: URL) -> (count: Int, size: UInt64) {
        guard let items = try? contents(of: directory) else { return (0, 0) }
        return (items.count, items.reduce(UInt64(0)) { $0 &+ $1.size })
    }

    // MARK: - Silme

    /// Çöp Kutusu'na taşır. Kalıcı silme yok: kullanıcı fikrini
    /// değiştirdiğinde geri alabilmeli.
    ///
    /// Yönetilen alanın dışındaki hiçbir şey buradan silinemiyor — dışarıdan
    /// gelen bir yol (bağlanmış klasör, sembolik bağ) kullanıcının kendi
    /// dosyalarını götürebilirdi.
    func moveToTrash(_ url: URL) throws {
        guard isInsideStorage(url) else { throw StorageError.outsideStorage }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw StorageError.copyFailed(
                name: url.lastPathComponent,
                reason: error.localizedDescription
            )
        }
    }

    // MARK: - Sınır denetimi

    /// URL yönetilen alanın içinde mi?
    ///
    /// İki taraf da önce standartlaştırılıp sembolik bağları çözülüyor:
    /// `Storage/x/../../etc` gibi bir yol da, Storage içinden dışarı bakan
    /// bir sembolik bağ da böylece dışarıda kalıyor. Karşılaştırma metin
    /// öneki değil **yol bileşeni** üzerinden: "…/Storage2" adlı bir dizin
    /// metin olarak "…/Storage" ile başlıyor ama içinde değil.
    func isInsideStorage(_ url: URL) -> Bool {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()

        let rootComponents = resolvedRoot.pathComponents
        let components = resolved.pathComponents

        guard components.count > rootComponents.count else {
            return components == rootComponents
        }
        return Array(components.prefix(rootComponents.count)) == rootComponents
    }
}
