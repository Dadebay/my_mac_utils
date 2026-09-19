import Foundation
import SwiftData
import Testing
@testable import GlassDoKit

/// Yönetilen dosya alanının testleri.
///
/// Hepsi geçici bir kök dizinde çalışıyor: hiçbir test kullanıcının gerçek
/// `Application Support` klasörüne ya da ev dizinine dokunmuyor. Servisin
/// kökü dışarıdan alması zaten bunun için.
struct ManagedStorageTests {

    /// Her test için kendi geçici kökü.
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassDoStorageTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeSourceFile(named name: String, contents: String = "merhaba") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassDoSource-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - Kök ve klasör

    @Test("Storage kökü oluşturuluyor")
    func createsRoot() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        try service.prepareRoot()

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("Geçerli isimle gerçek bir klasör oluşturuluyor")
    func createsFolder() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let created = try service.createFolder(named: "  Fotoğraflar  ")

        // Ad kırpılıyor, dizin adı ise UUID.
        #expect(created.name == "Fotoğraflar")
        #expect(UUID(uuidString: created.url.lastPathComponent) != nil)
        #expect(FileManager.default.fileExists(atPath: created.url.path))
        #expect(service.isInsideStorage(created.url))
    }

    @Test("Boş ve geçersiz klasör isimleri reddediliyor")
    func rejectsInvalidNames() {
        let invalid = ["", "   ", "\n", ".", "..", "...", "a/b", "a:b", "a\u{0}b", "\u{1}"]

        for name in invalid {
            #expect(throws: ManagedStorageService.StorageError.invalidFolderName) {
                try ManagedStorageService.sanitized(folderName: name)
            }
        }
    }

    @Test("Aynı adlı iki klasör çakışmadan oluşturuluyor")
    func allowsDuplicateDisplayNames() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let first = try service.createFolder(named: "Belgeler")
        let second = try service.createFolder(named: "Belgeler")

        #expect(first.name == second.name)
        #expect(first.url != second.url)
        #expect(FileManager.default.fileExists(atPath: first.url.path))
        #expect(FileManager.default.fileExists(atPath: second.url.path))
    }

    // MARK: - Dosya alma

    @Test("Dosya klasöre kopyalanıyor")
    func copiesFile() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let folder = try service.createFolder(named: "Medya")
        let source = try makeSourceFile(named: "Photo.jpg")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let destination = try service.importFile(at: source, into: folder.url)

        #expect(destination.lastPathComponent == "Photo.jpg")
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(service.isInsideStorage(destination))
    }

    @Test("Aynı isimli dosya için “Photo 2.jpg” üretiliyor")
    func resolvesNameCollisions() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let folder = try service.createFolder(named: "Medya")
        let source = try makeSourceFile(named: "Photo.jpg")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let first = try service.importFile(at: source, into: folder.url)
        let second = try service.importFile(at: source, into: folder.url)
        let third = try service.importFile(at: source, into: folder.url)

        #expect(first.lastPathComponent == "Photo.jpg")
        #expect(second.lastPathComponent == "Photo 2.jpg")
        #expect(third.lastPathComponent == "Photo 3.jpg")
        // Üzerine yazılmadı: üçü de duruyor.
        #expect(try service.contents(of: folder.url).count == 3)
    }

    @Test("Uzantısız dosyada da çakışma güvenle çözülüyor")
    func resolvesCollisionsWithoutExtension() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let folder = try service.createFolder(named: "Notlar")
        let source = try makeSourceFile(named: "README")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        _ = try service.importFile(at: source, into: folder.url)
        let second = try service.importFile(at: source, into: folder.url)

        #expect(second.lastPathComponent == "README 2")
    }

    @Test("Kopyalamadan sonra orijinal dosya yerinde kalıyor")
    func leavesSourceUntouched() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let folder = try service.createFolder(named: "Medya")
        let source = try makeSourceFile(named: "Song.mp3", contents: "ses")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        _ = try service.importFile(at: source, into: folder.url)

        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOf: source, encoding: .utf8) == "ses")
    }

    @Test("Klasör içe aktarma açıkça reddediliyor, sessizce yutulmuyor")
    func rejectsDirectoryImport() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let folder = try service.createFolder(named: "Medya")
        let other = try service.createFolder(named: "Kaynak")

        #expect(throws: ManagedStorageService.StorageError.directoriesNotSupported) {
            try service.importFile(at: other.url, into: folder.url)
        }
    }

    // MARK: - Sınır denetimi

    @Test("Storage dışına path traversal engelleniyor")
    func blocksPathTraversal() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        try service.prepareRoot()

        let escaped = root.appendingPathComponent("../kacis", isDirectory: true)
        #expect(!service.isInsideStorage(escaped))
        #expect(!service.isInsideStorage(root.appendingPathComponent("../../etc")))

        let source = try makeSourceFile(named: "x.txt")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        #expect(throws: ManagedStorageService.StorageError.outsideStorage) {
            try service.importFile(at: source, into: escaped)
        }
    }

    @Test("Adı Storage ile başlayan komşu dizin içeride sayılmıyor")
    func doesNotMatchSiblingPrefix() {
        let root = makeRoot()
        let service = ManagedStorageService(root: root)

        // Metin öneki olarak eşleşir ama yol bileşeni olarak eşleşmez.
        let sibling = URL(fileURLWithPath: root.path + "2")
        #expect(!service.isInsideStorage(sibling))
    }

    @Test("Sembolik bağla dışarı çıkış engelleniyor")
    func blocksSymlinkEscape() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        try service.prepareRoot()

        // Storage dışında gerçek bir dizin ve içinde bir dosya.
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassDoOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let secret = outside.appendingPathComponent("gizli.txt")
        try Data("gizli".utf8).write(to: secret)

        // Storage'ın içinden dışarı bakan bir bağ.
        let link = root.appendingPathComponent("kapi", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        #expect(!service.isInsideStorage(link))
        #expect(!service.isInsideStorage(link.appendingPathComponent("gizli.txt")))

        // Bağın ardındaki dosya listelenemiyor ve silinemiyor.
        #expect(throws: ManagedStorageService.StorageError.outsideStorage) {
            try service.contents(of: link)
        }
        #expect(throws: ManagedStorageService.StorageError.outsideStorage) {
            try service.moveToTrash(link.appendingPathComponent("gizli.txt"))
        }
        // Dosya hâlâ yerinde.
        #expect(FileManager.default.fileExists(atPath: secret.path))
    }

    @Test("Storage dışındaki dosya Çöp Kutusu'na taşınamıyor")
    func refusesToTrashOutsideFiles() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        try service.prepareRoot()

        let source = try makeSourceFile(named: "kullanici-dosyasi.txt")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        #expect(throws: ManagedStorageService.StorageError.outsideStorage) {
            try service.moveToTrash(source)
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - Listeleme ve silme

    @Test("İçerik boyut, tarih ve türle birlikte listeleniyor")
    func listsContentsWithMetadata() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let folder = try service.createFolder(named: "Karışık")

        let text = try makeSourceFile(named: "Not.txt", contents: "on karakter")
        defer { try? FileManager.default.removeItem(at: text.deletingLastPathComponent()) }
        let before = Date().addingTimeInterval(-2)
        _ = try service.importFile(at: text, into: folder.url)

        let items = try service.contents(of: folder.url)

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.name == "Not.txt")
        #expect(item.size == UInt64(Data("on karakter".utf8).count))
        #expect(item.modifiedAt >= before)
        #expect(!item.isDirectory)
    }

    @Test("Liste ada göre doğal sırayla geliyor")
    func sortsContentsNaturally() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let folder = try service.createFolder(named: "Sıra")

        for name in ["b.txt", "a.txt", "c.txt"] {
            let source = try makeSourceFile(named: name)
            defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
            _ = try service.importFile(at: source, into: folder.url)
        }

        let names = try service.contents(of: folder.url).map(\.name)
        #expect(names == ["a.txt", "b.txt", "c.txt"])
    }

    @Test("Yönetilen dosya Çöp Kutusu'na taşınıyor, kalıcı silinmiyor")
    func movesManagedFileToTrash() throws {
        // Yalnızca geçici kök: silme testi kullanıcının dizinlerine
        // hiçbir koşulda dokunmuyor.
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ManagedStorageService(root: root)
        let folder = try service.createFolder(named: "Geçici")
        let source = try makeSourceFile(named: "silinecek-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let copied = try service.importFile(at: source, into: folder.url)
        try service.moveToTrash(copied)

        #expect(!FileManager.default.fileExists(atPath: copied.path))
        #expect(try service.contents(of: folder.url).isEmpty)
        // Kaynak dosyaya dokunulmadı.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - Veri modeli

    @Test("Mevcut FolderBookmark kayıtları korunuyor ve bağlanmış sayılıyor")
    @MainActor
    func preservesExistingFolderBookmarks() throws {
        let schema = Schema([Task.self, Tag.self, FolderBookmark.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Eski akışın oluşturduğu kayıt: yeni alan verilmemiş.
        let linked = FolderBookmark(path: "/Users/test/Documents", name: "Documents")
        context.insert(linked)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<FolderBookmark>())
        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.path == "/Users/test/Documents")
        #expect(stored.name == "Documents")
        // Varsayılan false: eski kayıtlar bağlanmış klasör olarak okunuyor,
        // yani üzerlerinde yıkıcı işlem yapılmıyor.
        #expect(stored.isManagedStorage == false)
    }

    @Test("Yönetilen klasör kaydı işaretiyle saklanıyor")
    @MainActor
    func storesManagedFlag() throws {
        let schema = Schema([Task.self, Tag.self, FolderBookmark.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        context.insert(FolderBookmark(path: "/tmp/x", name: "Medya", isManagedStorage: true))
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<FolderBookmark>()).first)
        #expect(stored.isManagedStorage)
    }
}
