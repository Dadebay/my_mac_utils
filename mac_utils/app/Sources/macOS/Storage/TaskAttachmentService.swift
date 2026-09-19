import Foundation
import GlassDoKit
import SwiftData

/// Bir göreve dosya/klasör/pano metni iliştirmenin tek yeri.
///
/// Kaynak dosya hiçbir zaman kopyalanmıyor veya taşınmıyor — yalnızca
/// security-scoped bir bookmark saklanıyor. Kaldırma da yalnızca bu kaydı
/// siler, diske asla dokunmaz (Shelf dosyası da, kullanıcının kendi dosyası
/// da olduğu yerde kalır).
@MainActor
enum TaskAttachmentService {
    static let maxAttachmentsPerTask = 30

    enum TaskAttachmentError: LocalizedError, Equatable {
        case limitReached
        case duplicate
        case bookmarkFailed

        var errorDescription: String? {
            switch self {
            case .limitReached: L10n.attachmentLimitReached
            case .duplicate: L10n.attachmentDuplicate
            case .bookmarkFailed: L10n.attachmentBookmarkFailed
            }
        }
    }

    @discardableResult
    static func addFile(
        at url: URL,
        kind: TaskAttachmentKind,
        to task: Task,
        in context: ModelContext
    ) throws -> TaskAttachment {
        let existing = task.attachments ?? []
        guard existing.count < maxAttachmentsPerTask else {
            throw TaskAttachmentError.limitReached
        }

        let standardizedTarget = url.standardizedFileURL.resolvingSymlinksInPath().path
        let isDuplicate = existing.contains { attachment in
            guard let resolved = attachment.resolveBookmark() else { return false }
            return resolved.url.standardizedFileURL.resolvingSymlinksInPath().path == standardizedTarget
        }
        guard !isDuplicate else { throw TaskAttachmentError.duplicate }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let bookmark = try? TaskAttachment.makeBookmark(for: url) else {
            throw TaskAttachmentError.bookmarkFailed
        }

        let attachment = TaskAttachment(displayName: url.lastPathComponent, kind: kind)
        attachment.bookmarkData = bookmark
        attachment.task = task
        context.insert(attachment)
        try? context.save()
        return attachment
    }

    @discardableResult
    static func addClipboardText(
        _ text: String,
        to task: Task,
        in context: ModelContext
    ) throws -> TaskAttachment {
        let existing = task.attachments ?? []
        guard existing.count < maxAttachmentsPerTask else {
            throw TaskAttachmentError.limitReached
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? text : String(trimmed.prefix(60))
        let attachment = TaskAttachment(displayName: displayName, kind: .clipboardText)
        attachment.copiedText = text
        attachment.task = task
        context.insert(attachment)
        try? context.save()
        return attachment
    }

    /// Kaydı siler — diske **asla** dokunmaz.
    static func remove(_ attachment: TaskAttachment, in context: ModelContext) {
        context.delete(attachment)
        try? context.save()
    }

    /// Stale/eksik bookmark için yeniden bookmark üretir, aynı kaydı günceller.
    static func relink(_ attachment: TaskAttachment, to url: URL, in context: ModelContext) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let bookmark = try? TaskAttachment.makeBookmark(for: url) else {
            throw TaskAttachmentError.bookmarkFailed
        }
        attachment.bookmarkData = bookmark
        attachment.displayName = url.lastPathComponent
        try? context.save()
    }
}
