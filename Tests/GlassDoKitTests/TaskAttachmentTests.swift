import Testing
import Foundation
import SwiftData
@testable import GlassDoKit

@MainActor
struct TaskAttachmentTests {
    private func makeContext() throws -> ModelContext {
        let container = try AppStore.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    private func makeTempFile(named name: String = "\(UUID().uuidString).txt") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try "içerik".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("Bookmark round-trip aynı dosya yoluna dönüyor")
    func bookmarkRoundTrip() throws {
        let fileURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let bookmark = try TaskAttachment.makeBookmark(for: fileURL)
        let attachment = TaskAttachment(displayName: fileURL.lastPathComponent, kind: .file)
        attachment.bookmarkData = bookmark

        let resolved = attachment.resolveBookmark()
        #expect(resolved != nil)
        #expect(resolved?.url.standardizedFileURL.path == fileURL.standardizedFileURL.path)
        #expect(resolved?.isStale == false)
    }

    @Test("Aynı dosyanın iki kez eklenmesi .duplicate fırlatıyor")
    func duplicateFileThrows() throws {
        let ctx = try makeContext()
        let task = Task(title: "görev")
        ctx.insert(task)
        try ctx.save()

        let fileURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try TaskAttachmentService.addFile(at: fileURL, kind: .file, to: task, in: ctx)

        #expect(throws: TaskAttachmentService.TaskAttachmentError.duplicate) {
            try TaskAttachmentService.addFile(at: fileURL, kind: .file, to: task, in: ctx)
        }
    }

    @Test("30 sınırı aşıldığında .limitReached fırlatıyor")
    func limitReachedThrows() throws {
        let ctx = try makeContext()
        let task = Task(title: "görev")
        ctx.insert(task)
        try ctx.save()

        var files: [URL] = []
        for _ in 0..<TaskAttachmentService.maxAttachmentsPerTask {
            let url = try makeTempFile()
            files.append(url)
            _ = try TaskAttachmentService.addFile(at: url, kind: .file, to: task, in: ctx)
        }
        defer { for url in files { try? FileManager.default.removeItem(at: url) } }

        let overflow = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: overflow) }

        #expect(throws: TaskAttachmentService.TaskAttachmentError.limitReached) {
            try TaskAttachmentService.addFile(at: overflow, kind: .file, to: task, in: ctx)
        }
    }

    @Test("Üst görev silinince attachment kaydı da siliniyor ama fiziksel dosya diskte kalıyor")
    func cascadeDeleteKeepsPhysicalFile() throws {
        let ctx = try makeContext()
        let task = Task(title: "görev")
        ctx.insert(task)
        try ctx.save()

        let fileURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try TaskAttachmentService.addFile(at: fileURL, kind: .file, to: task, in: ctx)
        try ctx.save()
        #expect(task.attachments?.count == 1)

        ctx.delete(task)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<TaskAttachment>())
        #expect(remaining.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("Kaldırma yalnızca kaydı siler, dosyaya dokunmaz")
    func removeKeepsPhysicalFile() throws {
        let ctx = try makeContext()
        let task = Task(title: "görev")
        ctx.insert(task)
        try ctx.save()

        let fileURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let attachment = try TaskAttachmentService.addFile(at: fileURL, kind: .file, to: task, in: ctx)
        TaskAttachmentService.remove(attachment, in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<TaskAttachment>())
        #expect(remaining.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
