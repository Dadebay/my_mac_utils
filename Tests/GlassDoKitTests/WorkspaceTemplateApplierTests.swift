import Testing
import Foundation
import SwiftData
@testable import GlassDoKit

@MainActor
struct WorkspaceTemplateApplierTests {
    private func makeContext() throws -> ModelContext {
        let container = try AppStore.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("Boş bağlamda önizleme tüm etiket ve görevleri yeni sayıyor")
    func previewOnEmptyContextCountsEverythingAsNew() throws {
        let ctx = try makeContext()
        let content = WorkspaceTemplateKind.developer.content

        let preview = WorkspaceTemplateApplier.preview(.developer, in: ctx)

        #expect(preview.newTagCount == content.allTags.count)
        #expect(preview.reusedTagCount == 0)
        #expect(preview.newTaskCount == content.sampleTasks.count)
        #expect(preview.skippedTaskCount == 0)
        #expect(!preview.isNoOp)
    }

    @Test("Uygulama tam olarak beklenen sayıda etiket ve görev ekliyor")
    func applyCreatesExpectedTagsAndTasks() throws {
        let ctx = try makeContext()
        let content = WorkspaceTemplateKind.developer.content

        let result = WorkspaceTemplateApplier.apply(.developer, in: ctx)

        let tags = WorkspaceTestSupport.allTags(in: ctx)
        let tasks = try ctx.fetch(FetchDescriptor<Task>())

        #expect(result.newTagCount == content.allTags.count)
        #expect(result.newTaskCount == content.sampleTasks.count)
        #expect(tags.count == content.allTags.count)
        #expect(tasks.count == content.sampleTasks.count)
        #expect(Set(tags.map(\.name)) == Set(content.allTags.map(\.name)))
    }

    @Test("Örnek görevler doğru etiketlere bağlanıyor")
    func sampleTasksAreLinkedToCorrectTags() throws {
        let ctx = try makeContext()
        WorkspaceTemplateApplier.apply(.developer, in: ctx)

        let tasks = try ctx.fetch(FetchDescriptor<Task>())
        let content = WorkspaceTemplateKind.developer.content

        for spec in content.sampleTasks {
            guard let task = tasks.first(where: { $0.title == spec.title }) else {
                Issue.record("Görev bulunamadı: \(spec.title)")
                continue
            }
            let taskTagNames = Set((task.tags ?? []).map(\.name))
            #expect(taskTagNames == Set(spec.tagNames))
        }
    }

    @Test("Aynı şablon ikinci kez uygulanınca yeni etiket/görev eklenmiyor")
    func applyingTwiceIsIdempotent() throws {
        let ctx = try makeContext()
        WorkspaceTemplateApplier.apply(.developer, in: ctx)

        let tagCountAfterFirst = WorkspaceTestSupport.allTags(in: ctx).count
        let taskCountAfterFirst = try ctx.fetch(FetchDescriptor<Task>()).count

        let secondResult = WorkspaceTemplateApplier.apply(.developer, in: ctx)

        let tagCountAfterSecond = WorkspaceTestSupport.allTags(in: ctx).count
        let taskCountAfterSecond = try ctx.fetch(FetchDescriptor<Task>()).count

        #expect(secondResult.isNoOp)
        #expect(secondResult.newTagCount == 0)
        #expect(secondResult.newTaskCount == 0)
        #expect(tagCountAfterSecond == tagCountAfterFirst)
        #expect(taskCountAfterSecond == taskCountAfterFirst)
    }

    @Test("Şablon uygulamak mevcut, ilgisiz görevleri silmiyor")
    func applyingDoesNotTouchExistingUnrelatedTasks() throws {
        let ctx = try makeContext()
        let existing = Task(title: "Kullanıcının kendi görevi")
        existing.sortIndex = 0
        ctx.insert(existing)
        try ctx.save()

        WorkspaceTemplateApplier.apply(.developer, in: ctx)

        let tasks = try ctx.fetch(FetchDescriptor<Task>())
        #expect(tasks.contains { $0.title == "Kullanıcının kendi görevi" })
    }

    @Test("Aynı adlı etiket zaten varsa yeniden oluşturulmuyor, mevcut kullanılıyor")
    func existingTagWithSameNameIsReused() throws {
        let ctx = try makeContext()
        let content = WorkspaceTemplateKind.developer.content
        guard let firstTagName = content.allTags.first?.name else {
            Issue.record("Şablonun etiketi yok")
            return
        }

        let preExisting = WorkspaceTestSupport.makeTag(name: firstTagName)
        preExisting.colorHex = "#000000"
        ctx.insert(preExisting)
        try ctx.save()

        let result = WorkspaceTemplateApplier.apply(.developer, in: ctx)

        let tags = WorkspaceTestSupport.allTags(in: ctx)
        let matching = tags.filter { $0.name == firstTagName }

        #expect(matching.count == 1, "Aynı adlı etiketten iki tane oluşmamalı")
        #expect(matching.first?.colorHex == "#000000", "Var olan etiketin rengi değişmemeli")
        #expect(result.reusedTagCount >= 1)
    }

    @Test("İki farklı şablon art arda uygulanınca ikisinin de görevleri ekleniyor")
    func applyingTwoDifferentTemplatesAddsBoth() throws {
        let ctx = try makeContext()
        WorkspaceTemplateApplier.apply(.developer, in: ctx)
        WorkspaceTemplateApplier.apply(.student, in: ctx)

        let tasks = try ctx.fetch(FetchDescriptor<Task>())
        let developerTitles = Set(WorkspaceTemplateKind.developer.content.sampleTasks.map(\.title))
        let studentTitles = Set(WorkspaceTemplateKind.student.content.sampleTasks.map(\.title))

        #expect(developerTitles.isSubset(of: Set(tasks.map(\.title))))
        #expect(studentTitles.isSubset(of: Set(tasks.map(\.title))))
    }

    @Test("Her şablonda 2-4 proje etiketi ve 4-8 genel etiket var")
    func everyTemplateRespectsCountBounds() {
        for kind in WorkspaceTemplateKind.allCases {
            let content = kind.content
            #expect((2...4).contains(content.projectTags.count), "\(kind): proje etiket sayısı 2-4 dışında")
            #expect((4...8).contains(content.labelTags.count), "\(kind): genel etiket sayısı 4-8 dışında")
            #expect(content.sampleTasks.count == 3, "\(kind): örnek görev sayısı 3 değil")
        }
    }

    @Test("Her örnek görev en az bir gerçek etikete bağlanabiliyor")
    func everySampleTaskReferencesKnownTagNames() {
        for kind in WorkspaceTemplateKind.allCases {
            let content = kind.content
            let knownNames = Set(content.allTags.map(\.name))
            for task in content.sampleTasks {
                #expect(!task.tagNames.isEmpty, "\(kind): '\(task.title)' hiçbir etikete bağlı değil")
                for name in task.tagNames {
                    #expect(knownNames.contains(name), "\(kind): '\(task.title)' bilinmeyen etikete atıfta bulunuyor: \(name)")
                }
            }
        }
    }
}
