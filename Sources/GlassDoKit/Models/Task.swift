import SwiftData
import Foundation

@Model
public final class Task {
    public var id: UUID = UUID()
    public var title: String = ""
    public var isCompleted: Bool = false
    public var createdAt: Date = Date()
    public var completedAt: Date?
    public var sortIndex: Int = 0
    /// Satır türü (`TaskKind`). Ham değer olarak saklanıyor — mevcut
    /// kayıtlar varsayılan değerle görev olarak açılır.
    public var kindRaw: Int = TaskKind.todo.rawValue

    @Relationship(inverse: \Tag.tasks)
    public var tags: [Tag]? = []

    public init(title: String = "", kind: TaskKind = .todo) {
        self.title = title
        self.kindRaw = kind.rawValue
    }
}

public extension Task {
    /// Uzantıda tanımlı — SwiftData yalnızca `kindRaw`'ı saklar.
    var kind: TaskKind {
        get { TaskKind(rawValue: kindRaw) ?? .todo }
        set { kindRaw = newValue.rawValue }
    }
}

public extension Task {
    static func activePredicate() -> Predicate<Task> {
        #Predicate<Task> { task in !task.isCompleted }
    }

    static func completedPredicate() -> Predicate<Task> {
        #Predicate<Task> { task in task.isCompleted }
    }
}
