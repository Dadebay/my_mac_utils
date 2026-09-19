import Foundation

/// Doğal dil hızlı giriş ayrıştırmasının sonucu. Tanınmayan kelimeler
/// `title` içinde kalır — yanlış tahmin yerine hiçbir şeyi kaybetmemek
/// önceliktir.
public struct QuickAddParseResult: Sendable, Equatable {
    public var title: String
    public var dueDate: Date?
    public var priority: Priority?
    public var tagNames: [String]

    public init(title: String, dueDate: Date? = nil, priority: Priority? = nil, tagNames: [String] = []) {
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.tagNames = tagNames
    }
}

/// Küçük, saf ve test edilebilir bir hızlı giriş ayrıştırıcı. SwiftUI veya
/// SwiftData import etmez — Panel ve ana pencere Quick Add'i aynı sonucu
/// üretir (bkz. `TaskQuickAddService`).
///
/// V1 kapsamı yalnızca Türkçe: `yarın`, `bugün`, hafta günü adları,
/// `saat 15:00` / çıplak `15:00`, `#etiket`, `!yüksek`/`!orta`/`!düşük`.
public enum QuickAddParser {
    private static let weekdayNames: [String: Int] = [
        "pazar": 1, "pazartesi": 2, "salı": 3, "sali": 3,
        "çarşamba": 4, "carsamba": 4, "perşembe": 5, "persembe": 5,
        "cuma": 6, "cumartesi": 7,
    ]

    private static let priorityTokens: [String: Priority] = [
        "!yüksek": .high, "!yuksek": .high,
        "!orta": .medium,
        "!düşük": .low, "!dusuk": .low,
    ]

    private static let timePattern = try! NSRegularExpression(pattern: #"^([01]?\d|2[0-3]):([0-5]\d)$"#)

    public static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> QuickAddParseResult {
        var remainingTokens: [String] = []
        var dueDate: Date?
        var priority: Priority?
        var tagNames: [String] = []
        var timeComponents: (hour: Int, minute: Int)?

        let tokens = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lowered = token.lowercased(with: Locale(identifier: "tr"))

            if let matchedPriority = priorityTokens[lowered] {
                priority = matchedPriority
                index += 1
                continue
            }

            if token.hasPrefix("#"), token.count > 1 {
                tagNames.append(String(token.dropFirst()))
                index += 1
                continue
            }

            if lowered == "bugün" || lowered == "bugun" {
                dueDate = calendar.startOfDay(for: now)
                index += 1
                continue
            }

            if lowered == "yarın" || lowered == "yarin" {
                dueDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                index += 1
                continue
            }

            if let weekday = weekdayNames[lowered] {
                dueDate = nextDate(forWeekday: weekday, after: now, calendar: calendar)
                index += 1
                continue
            }

            if lowered == "saat", index + 1 < tokens.count, let parsed = parseTime(tokens[index + 1]) {
                timeComponents = parsed
                index += 2
                continue
            }

            if let parsed = parseTime(token) {
                timeComponents = parsed
                index += 1
                continue
            }

            remainingTokens.append(token)
            index += 1
        }

        if let timeComponents {
            let base = dueDate ?? calendar.startOfDay(for: now)
            dueDate = calendar.date(
                bySettingHour: timeComponents.hour,
                minute: timeComponents.minute,
                second: 0,
                of: base
            ) ?? base
        }

        let title = remainingTokens.joined(separator: " ")
        return QuickAddParseResult(title: title, dueDate: dueDate, priority: priority, tagNames: tagNames)
    }

    private static func parseTime(_ token: String) -> (hour: Int, minute: Int)? {
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        guard let match = timePattern.firstMatch(in: token, range: range),
              let hourRange = Range(match.range(at: 1), in: token),
              let minuteRange = Range(match.range(at: 2), in: token),
              let hour = Int(token[hourRange]),
              let minute = Int(token[minuteRange])
        else { return nil }
        return (hour, minute)
    }

    private static func nextDate(forWeekday weekday: Int, after now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let todayWeekday = calendar.component(.weekday, from: today)
        var daysAhead = weekday - todayWeekday
        if daysAhead <= 0 { daysAhead += 7 }
        return calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today
    }
}
