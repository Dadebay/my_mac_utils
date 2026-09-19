import Foundation
import SwiftData

/// `QuickAddParser`'ın hangi alanlarının bastırılabileceğini belirtir —
/// kullanıcı hızlı eklemede önerilen bir chip'i kaldırdığında o alan
/// oluşturulan görevden dışlanır (ham metin değişmez).
public enum QuickAddField: Sendable {
    case dueDate
    case priority
}

/// Panel ve ana pencere Quick Add'in paylaştığı tek görev oluşturma
/// servisi — ikisi de aynı ayrıştırma/oluşturma davranışını kullanır.
@MainActor
public enum TaskQuickAddService {
    @discardableResult
    public static func makeTask(
        from rawInput: String,
        in context: ModelContext,
        existingTasks: [Task],
        suppressedFields: Set<QuickAddField> = []
    ) -> Task? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parsed = QuickAddParser.parse(trimmed)
        let title = parsed.title.isEmpty ? trimmed : parsed.title

        let task = Task(title: title)
        task.sortIndex = (existingTasks.map(\.sortIndex).max() ?? -1) + 1
        if !suppressedFields.contains(.dueDate) {
            task.dueDate = parsed.dueDate
        }
        if !suppressedFields.contains(.priority), let priority = parsed.priority {
            task.priority = priority
        }
        task.tags = resolveTags(named: parsed.tagNames, in: context)

        context.insert(task)
        return task
    }

    private static func resolveTags(named names: [String], in context: ModelContext) -> [Tag] {
        guard !names.isEmpty else { return [] }
        var resolved: [Tag] = []
        for name in names {
            let descriptor = FetchDescriptor<Tag>(predicate: #Predicate<Tag> { $0.name == name })
            if let existing = try? context.fetch(descriptor).first {
                resolved.append(existing)
            } else {
                let tag = Tag(name: name)
                context.insert(tag)
                resolved.append(tag)
            }
        }
        return resolved
    }
}
