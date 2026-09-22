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
    public var notes: String = ""
    public var dueDate: Date?
    public var priorityRaw: Int = Priority.none.rawValue
    /// `RecurrenceRule`'ın JSON kodlanmış hâli — bkz. `Task.recurrenceRule`.
    public var recurrenceData: Data?

    @Relationship(inverse: \Tag.tasks)
    public var tags: [Tag]? = []

    /// Bir görevin en fazla bir üst görevi olur. Ana görev silinince alt
    /// görevler de silinir (cascade) — bağımsız satır olarak ortada kalmazlar.
    public var parentTask: Task?
    @Relationship(deleteRule: .cascade, inverse: \Task.parentTask)
    public var subtasks: [Task]? = []

    @Relationship(deleteRule: .cascade, inverse: \TaskAttachment.task)
    public var attachments: [TaskAttachment]? = []

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

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    /// Uzantıda tanımlı — SwiftData yalnızca ham `recurrenceData`'yı saklar.
    var recurrenceRule: RecurrenceRule? {
        get {
            guard let recurrenceData else { return nil }
            return try? JSONDecoder().decode(RecurrenceRule.self, from: recurrenceData)
        }
        set {
            recurrenceData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }
}

public extension Task {
    /// Alt görevler ana listeye bağımsız satır olarak düşmez — yalnızca
    /// üst görevi olmayan (`parentTask == nil`) kayıtlar aktif/tamamlanan
    /// listelerinde görünür.
    static func activePredicate() -> Predicate<Task> {
        #Predicate<Task> { task in !task.isCompleted && task.parentTask == nil }
    }

    static func completedPredicate() -> Predicate<Task> {
        #Predicate<Task> { task in task.isCompleted && task.parentTask == nil }
    }

    /// Yalnızca gerçek görevler (`.todo`) — Panel'in kompakt kontrol
    /// listesi için. Not editöründe (`PoppedNoteView`) başlık/metin/
    /// ayırıcı/boşluk satırları da aynı `Task` tablosunda yaşıyor;
    /// `activePredicate()`'i doğrudan kullanmak panelde onay kutusuz,
    /// metinsiz "hayalet" satırlar olarak sızmalarına yol açıyordu —
    /// üstelik tıklanırsa formatlama satırını yanlışlıkla tamamlıyordu.
    static func activeTodoPredicate() -> Predicate<Task> {
        let todoKind = TaskKind.todo.rawValue
        return #Predicate<Task> { task in
            !task.isCompleted && task.parentTask == nil && task.kindRaw == todoKind
        }
    }

    static func completedTodoPredicate() -> Predicate<Task> {
        let todoKind = TaskKind.todo.rawValue
        return #Predicate<Task> { task in
            task.isCompleted && task.parentTask == nil && task.kindRaw == todoKind
        }
    }
}
