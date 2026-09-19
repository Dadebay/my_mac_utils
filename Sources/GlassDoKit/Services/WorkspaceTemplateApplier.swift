import Foundation
import SwiftData

/// Bir şablonu uygulamanın sonucu: kaç yeni etiket/görev eklendi, kaçı
/// zaten vardı (bu yüzden atlandı). `preview(_:in:)` ve `apply(_:in:)`
/// aynı tipi döndürür — önizleme, uygulamadan önce kullanıcıya tam olarak
/// ne olacağını gösteriyor.
public struct WorkspaceApplyResult: Sendable, Equatable {
    public let newTagCount: Int
    public let reusedTagCount: Int
    public let newTaskCount: Int
    public let skippedTaskCount: Int

    public init(newTagCount: Int, reusedTagCount: Int, newTaskCount: Int, skippedTaskCount: Int) {
        self.newTagCount = newTagCount
        self.reusedTagCount = reusedTagCount
        self.newTaskCount = newTaskCount
        self.skippedTaskCount = skippedTaskCount
    }

    public var isNoOp: Bool { newTagCount == 0 && newTaskCount == 0 }
}

/// Bir şablonu SwiftData'ya kopyalar. Mevcut veriyi asla silmez veya
/// yeniden sıralamaz; yalnızca eksik olanı ekler.
///
/// İdempotent: aynı şablon iki kez uygulanırsa aynı adlı etiketi tekrar
/// oluşturmaz (mevcut olanı kullanır), aynı başlıklı örnek görevi tekrar
/// eklemez. Bu, `TaskQuickAddService.resolveTags`'in ad-bazlı bul-ya-da-
/// oluştur deseniyle aynı mantık.
@MainActor
public enum WorkspaceTemplateApplier {
    public static func preview(_ kind: WorkspaceTemplateKind, in context: ModelContext) -> WorkspaceApplyResult {
        let content = kind.content
        let existingTagNames = Set(((try? context.fetch(FetchDescriptor<Tag>())) ?? []).map(\.name))
        let existingTaskTitles = Set(((try? context.fetch(FetchDescriptor<Task>())) ?? []).map(\.title))

        let allTagNames = content.allTags.map(\.name)
        let newTagCount = allTagNames.filter { !existingTagNames.contains($0) }.count
        let newTaskCount = content.sampleTasks.filter { !existingTaskTitles.contains($0.title) }.count

        return WorkspaceApplyResult(
            newTagCount: newTagCount,
            reusedTagCount: allTagNames.count - newTagCount,
            newTaskCount: newTaskCount,
            skippedTaskCount: content.sampleTasks.count - newTaskCount
        )
    }

    @discardableResult
    public static func apply(_ kind: WorkspaceTemplateKind, in context: ModelContext) -> WorkspaceApplyResult {
        let content = kind.content
        let result = preview(kind, in: context)

        var tagsByName: [String: Tag] = [:]
        for tag in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] {
            tagsByName[tag.name] = tag
        }

        for spec in content.allTags where tagsByName[spec.name] == nil {
            let tag = Tag(name: spec.name)
            tag.colorHex = spec.colorHex
            context.insert(tag)
            tagsByName[spec.name] = tag
        }

        let existingTasks = (try? context.fetch(FetchDescriptor<Task>())) ?? []
        let existingTaskTitles = Set(existingTasks.map(\.title))
        var nextSortIndex = (existingTasks.map(\.sortIndex).max() ?? -1) + 1

        for taskSpec in content.sampleTasks where !existingTaskTitles.contains(taskSpec.title) {
            let task = Task(title: taskSpec.title)
            task.sortIndex = nextSortIndex
            nextSortIndex += 1
            task.tags = taskSpec.tagNames.compactMap { tagsByName[$0] }
            context.insert(task)
        }

        try? context.save()
        return result
    }
}
