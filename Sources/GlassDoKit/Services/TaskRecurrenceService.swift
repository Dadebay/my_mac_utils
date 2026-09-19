import Foundation
import SwiftData

/// Tekrarlayan bir görev tamamlandığında bir sonraki örneği üretir.
/// Üretim yalnızca tamamlanma anında tetiklenir (uygulama açılışında/
/// foreground'da tarih bazlı bir tarama yapılmaz) — bu yüzden geçmişte
/// birden fazla tekrar asla üretilmez.
@MainActor
public enum TaskRecurrenceService {
    @discardableResult
    public static func materializeNextOccurrenceIfNeeded(
        for task: Task,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> Task? {
        guard task.isCompleted, let rule = task.recurrenceRule else { return nil }
        let base = task.dueDate ?? task.completedAt ?? .now
        guard let nextDate = RecurrenceEngine.nextOccurrence(after: base, rule: rule, calendar: calendar) else {
            return nil
        }

        let next = Task(title: task.title, kind: task.kind)
        next.notes = task.notes
        next.dueDate = nextDate
        next.priorityRaw = task.priorityRaw
        next.recurrenceData = task.recurrenceData
        next.tags = task.tags
        next.sortIndex = task.sortIndex
        context.insert(next)

        // Tamamlanmış kayıt artık geçmiş — tekrar kuralı yeni örneğe
        // "taşındı". Bu aynı zamanda bu fonksiyonun aynı görev üzerinde
        // yanlışlıkla iki kez çağrılmasına karşı doğal bir korumadır.
        task.recurrenceData = nil

        return next
    }
}
