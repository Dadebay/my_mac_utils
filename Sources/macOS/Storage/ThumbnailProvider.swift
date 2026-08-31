import AppKit
import QuickLookThumbnailing

/// Dosya önizlemeleri.
///
/// Üretim `QLThumbnailGenerator`'ın kendi kuyruğunda, yani ana iş
/// parçacığının dışında oluyor; sonuç bellekte önbelleğe alınıyor çünkü
/// panel her açılıp kapandığında aynı görselleri yeniden üretmek hem
/// yavaş hem de gereksiz.
///
/// Önbellek anahtarı dosyanın değiştirilme tarihini de taşıyor: aynı adla
/// değiştirilen bir dosya eski önizlemesiyle görünmesin.
@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 240
    }

    func cached(for item: StorageItem, size: CGFloat) -> NSImage? {
        cache.object(forKey: Self.key(for: item, size: size))
    }

    func thumbnail(for item: StorageItem, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = Self.key(for: item, size: size)
        if let hit = cache.object(forKey: key) { return hit }

        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: size, height: size),
            scale: max(scale, 1),
            representationTypes: .thumbnail
        )

        guard let representation = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
        else { return nil }

        let image = representation.nsImage
        cache.setObject(image, forKey: key)
        return image
    }

    private static func key(for item: StorageItem, size: CGFloat) -> NSString {
        "\(item.url.path)|\(item.modifiedAt.timeIntervalSince1970)|\(Int(size))" as NSString
    }
}
