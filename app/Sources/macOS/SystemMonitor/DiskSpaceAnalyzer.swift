import AppKit
import Foundation
import Observation
import GlassDoKit

struct StorageCandidate: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case application
        case package
        case file
    }

    let url: URL
    let allocatedSize: UInt64
    let kind: Kind
    /// Sistemin kendi uygulaması (`/System/Applications`, Cryptexes).
    /// Bunlar silinemez; SIP engelliyor. Çöp Kutusu düğmesini hiç
    /// göstermemek, basıp hata almaktan dürüst.
    var isSystem: Bool = false

    var canDelete: Bool { !isSystem }

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var parentName: String { url.deletingLastPathComponent().lastPathComponent }
}

/// Kurulu **uygulamaları** boyutlarına göre sıralar.
///
/// Kapsam bilerek dar: yalnızca uygulama klasörleri taranıyor ve yalnızca
/// `.app` paketleri aday oluyor. Önceki sürüm kullanıcının bütün ana
/// klasörünü geziyor, `.photoslibrary` gibi paketleri ve tekil dosyaları da
/// listeye katıyordu; başlık "En Büyük Uygulamalar" derken liste başka bir
/// şey gösteriyordu. Dosya ve klasör taraması ayrı bir akışın işi
/// (bkz. plans/014, Liste B).
///
/// Silme kalıcı değildir: yalnızca Finder'ın Çöp Kutusu mekanizmasını
/// kullanır ve sistem uygulamalarında hiç sunulmaz.
@MainActor
@Observable
final class DiskSpaceAnalyzer {
    static let shared = DiskSpaceAnalyzer()

    private(set) var items: [StorageCandidate] = []
    private(set) var isScanning = false
    private(set) var removingIDs: Set<String> = []
    private(set) var errorMessage: String?
    private var hasScanned = false

    private init() {}

    func scanIfNeeded() {
        guard !hasScanned else { return }
        scan()
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil

        _Concurrency.Task {
            let results = await _Concurrency.Task.detached(priority: .utility) {
                Self.findLargestItems(limit: 12)
            }.value

            items = results
            hasScanned = true
            isScanning = false
        }
    }

    func reveal(_ item: StorageCandidate) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Silme başarısız olduğunda, kullanıcıyı Finder'a yönlendirebilmek için
    /// hangi öğede takıldığımızı da tutuyoruz — çıplak bir hata metni
    /// "peki şimdi ne yapayım" sorusunu cevapsız bırakıyordu.
    private(set) var blockedItem: StorageCandidate?

    func moveToTrash(_ item: StorageCandidate) {
        guard !removingIDs.contains(item.id) else { return }

        // Önden tahmin edilmiyor: silinebilirlik yalnızca POSIX izinlerine
        // değil, macOS'un "Uygulama Yönetimi" (App Management) iznine de
        // bağlı ve o izin durumu sorgulanamıyor. `isDeletableFile` ile
        // `isWritableFile` ölçüldü, ikisi de yanlış cevap veriyor — biri
        // silinemeyene "silinebilir", öteki silinebilene "silinemez" diyor.
        // Bu yüzden deneniyor ve başarısızlık açıklanıyor.
        removingIDs.insert(item.id)
        errorMessage = nil
        blockedItem = nil

        NSWorkspace.shared.recycle([item.url]) { [weak self] _, error in
            _Concurrency.Task { @MainActor in
                guard let self else { return }
                self.removingIDs.remove(item.id)
                if error != nil {
                    // Tarama ile silme arasında izinler değişmiş olabilir;
                    // burada da aynı açıklamaya düşüyoruz.
                    self.errorMessage = L10n.storageNeedsAdminRights(item.name)
                    self.blockedItem = item
                } else {
                    self.items.removeAll { $0.id == item.id }
                }
            }
        }
    }

    func dismissError() {
        errorMessage = nil
        blockedItem = nil
    }

    nonisolated private static func findLargestItems(limit: Int) -> [StorageCandidate] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
        ]

        // Uygulamaların gerçekten durduğu yerler. Kullanıcının ana klasörü
        // listede yok: orada uygulama değil, veri var.
        let userRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
        // Sistem uygulamaları görünür ama silinemez: kapladıkları yeri
        // gizlemek, "diskim nerede dolu" sorusunu eksik yanıtlardı.
        let systemRoots = [
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
        ]
        let roots = userRoots + systemRoots
        var candidates: [StorageCandidate] = []
        var seenPaths = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            let isSystemRoot = systemRoots.contains { root.path.hasPrefix($0.path) }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                if _Concurrency.Task.isCancelled { return [] }

                guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                      values.isSymbolicLink != true
                else { continue }

                let isApplication = url.pathExtension.lowercased() == "app"

                // Yalnızca `.app`. `.photoslibrary`, `.xcodeproj`,
                // `.framework` gibi paketler de "paket" sayılıyor ama
                // uygulama değiller; listeye girdiklerinde başlık yalan
                // söylüyordu.
                if values.isDirectory == true, isApplication {
                    // Uygulamanın içine girilmiyor: paket bir kez kendi
                    // toplam boyutuyla sayılıyor, içindeki yardımcı
                    // uygulamalar ikinci kez sayılmamalı.
                    enumerator.skipDescendants()
                    let size = directoryAllocatedSize(at: url, resourceKeys: resourceKeys)
                    appendCandidate(
                        StorageCandidate(
                            url: url,
                            allocatedSize: size,
                            kind: .application,
                            isSystem: isSystemRoot
                        ),
                        to: &candidates,
                        seenPaths: &seenPaths,
                        workingLimit: limit * 3
                    )
                } else if values.isPackage == true, values.isDirectory == true {
                    // Uygulama olmayan paketlerin içine de girilmiyor:
                    // içlerindeki binlerce dosyayı gezmek taramayı
                    // uzatıyor, sonuca ise hiçbir şey katmıyor.
                    enumerator.skipDescendants()
                }
                // Tekil dosyalar listelenmiyor. Liste "en büyük uygulamalar"
                // diyor ve gerçekten öyle: arada beliren tek tük büyük
                // dosya (disk imajı, video) kullanıcıya silinebilir bir şey
                // gibi görünüyordu, oysa çoğu bir uygulamanın verisiydi.
            }
        }

        return Array(
            candidates
                .filter { $0.allocatedSize > 0 }
                .sorted { $0.allocatedSize > $1.allocatedSize }
                .prefix(limit)
        )
    }

    nonisolated private static func appendCandidate(
        _ candidate: StorageCandidate,
        to candidates: inout [StorageCandidate],
        seenPaths: inout Set<String>,
        workingLimit: Int
    ) {
        guard candidate.allocatedSize > 0, seenPaths.insert(candidate.id).inserted else { return }
        candidates.append(candidate)

        // Milyonlarca dosyanın URL'sini bellekte tutmak yerine yalnızca
        // sıralama için yeterli bir üst kümeyi taşı.
        if candidates.count > workingLimit * 2 {
            candidates.sort { $0.allocatedSize > $1.allocatedSize }
            candidates.removeSubrange(workingLimit..<candidates.count)
            seenPaths = Set(candidates.map(\.id))
        }
    }

    nonisolated private static func directoryAllocatedSize(
        at root: URL,
        resourceKeys: [URLResourceKey]
    ) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: UInt64 = 0
        while let url = enumerator.nextObject() as? URL {
            if _Concurrency.Task.isCancelled { return total }
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true
            else { continue }

            total += UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0, 0))
        }
        return total
    }
}
