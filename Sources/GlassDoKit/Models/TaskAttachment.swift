import SwiftData
import Foundation

/// `TaskAttachment.kindRaw` ham değeri — `Task.kindRaw` ile aynı desen.
public enum TaskAttachmentKind: Int, Sendable, CaseIterable {
    case file = 0
    case folder = 1
    case screenshot = 2
    case clipboardText = 3
}

/// Bir göreve iliştirilmiş dosya/klasör/ekran görüntüsü/pano metni.
/// Dosya/klasör/ekran görüntüsü türleri yalnızca `bookmarkData` tutar —
/// kaynak dosyanın kendisi hiçbir zaman kopyalanmaz veya taşınmaz.
@Model
public final class TaskAttachment {
    public var id: UUID = UUID()
    public var displayName: String = ""
    public var kindRaw: Int = TaskAttachmentKind.file.rawValue
    public var createdAt: Date = Date()
    /// `.file`/`.folder`/`.screenshot` için security-scoped bookmark.
    public var bookmarkData: Data?
    /// Yalnızca `.clipboardText` için: kopyalanan referans metni.
    public var copiedText: String?

    public var task: Task?

    public init(displayName: String = "", kind: TaskAttachmentKind = .file) {
        self.displayName = displayName
        self.kindRaw = kind.rawValue
    }
}

public extension TaskAttachment {
    var kind: TaskAttachmentKind {
        get { TaskAttachmentKind(rawValue: kindRaw) ?? .file }
        set { kindRaw = newValue.rawValue }
    }

    /// Bookmark verisinden gerçek dosya URL'sini çözer. `isStale == true`
    /// dönerse kullanıcıya "Dosyayı yeniden seç" eylemi gösterilmeli.
    /// Bookmark hiç çözülemezse (dosya taşındı/silindi) `nil` döner.
    func resolveBookmark() -> (url: URL, isStale: Bool)? {
        guard let bookmarkData else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }

    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
