import SwiftData
@testable import GlassDoKit

/// `WorkspaceTemplateApplierTests`'in `Tag` tipine bariz biçimde
/// erişebilmesi için — bu dosya kasıtlı olarak `Testing`'i import etmiyor.
/// `Testing` modülünün kendi `Tag` (test etiketleme) tipi ile `GlassDoKit.Tag`
/// aynı anda görünür olunca isim çakışması oluşuyor; modül adıyla nitelemek
/// de yetmiyor çünkü `GlassDoKit` içinde `GlassDoKit` adında bir struct da
/// var, o da modül adını gölgeliyor. Bu dosyanın hiç `Testing` import
/// etmemesi tek temiz çözüm.
enum WorkspaceTestSupport {
    @MainActor
    static func allTags(in context: ModelContext) -> [Tag] {
        (try? context.fetch(FetchDescriptor<Tag>())) ?? []
    }

    @MainActor
    static func makeTag(name: String) -> Tag {
        Tag(name: name)
    }
}
