import SwiftData
import Foundation

/// Bir uygulamayı bir göreve **veya** bir etikete bağlayan kural. Bir kural
/// ikisine birden bağlanamaz — `task` doluysa doğrudan görev kuralıdır,
/// aksi halde `tag` (etiket altındaki tüm görevler önerilir).
///
/// Etiket burada "proje" karşılığı: uygulamada ayrı bir Project modeli yok,
/// gruplama zaten `Tag` ile yapılıyor — ikinci bir gruplama kavramı eklemek
/// yalnızca kafa karıştırırdı.
@Model
public final class AppContextRule {
    public var id: UUID = UUID()
    public var bundleIdentifier: String = ""
    public var displayName: String?
    public var task: Task?
    public var tag: Tag?
    public var isEnabled: Bool = true
    public var sortIndex: Int = 0

    public init(
        bundleIdentifier: String,
        displayName: String? = nil,
        task: Task? = nil,
        tag: Tag? = nil,
        sortIndex: Int = 0
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.task = task
        self.tag = tag
        self.sortIndex = sortIndex
    }
}
