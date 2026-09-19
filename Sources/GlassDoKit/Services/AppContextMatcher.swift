import Foundation
import SwiftData

/// `AppContextRule` listesini aktif uygulamayla eşleştirip en fazla `limit`
/// görev önerisi üretir. Saf fonksiyon — `NSWorkspace`'e bağımlı değil,
/// bu yüzden doğrudan test edilebilir.
public enum AppContextMatcher {
    public static func matchingTasks(
        for bundleIdentifier: String?,
        rules: [AppContextRule],
        limit: Int = 3
    ) -> [Task] {
        guard let bundleIdentifier else { return [] }

        // Doğrudan görev kuralları etiket kurallarından önce gelir; eşit
        // öncelikte olanlar `sortIndex`e göre sıralanır.
        let candidates = rules
            .filter { $0.isEnabled && $0.bundleIdentifier == bundleIdentifier }
            .sorted { lhs, rhs in
                let lhsIsDirect = lhs.task != nil
                let rhsIsDirect = rhs.task != nil
                if lhsIsDirect != rhsIsDirect { return lhsIsDirect }
                return lhs.sortIndex < rhs.sortIndex
            }

        var seen = Set<PersistentIdentifier>()
        var results: [Task] = []

        for rule in candidates {
            if results.count >= limit { break }
            if let task = rule.task {
                guard !task.isCompleted, !seen.contains(task.persistentModelID) else { continue }
                seen.insert(task.persistentModelID)
                results.append(task)
            } else if let tag = rule.tag {
                for task in (tag.tasks ?? []) where !task.isCompleted {
                    guard results.count < limit, !seen.contains(task.persistentModelID) else { continue }
                    seen.insert(task.persistentModelID)
                    results.append(task)
                }
            }
        }

        return results
    }
}
