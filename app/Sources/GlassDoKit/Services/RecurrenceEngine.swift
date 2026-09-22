import Foundation

/// Bir tekrar kuralına göre bir sonraki oluşum tarihini hesaplayan saf
/// fonksiyon. Geçmişte birden fazla tekrar üretmeyi önlemek — uygulama
/// yalnızca görev tamamlandığı anda tek bir sonraki örnek üretir, bu yüzden
/// burada tarih bazlı toplu üretim/geri doldurma yoktur.
public enum RecurrenceEngine {
    public static func nextOccurrence(
        after date: Date,
        rule: RecurrenceRule,
        calendar: Calendar = .current
    ) -> Date? {
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)

        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)

        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)

        case .weekdays:
            guard !rule.weekdays.isEmpty else { return nil }
            for offset in 1...7 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
                if rule.weekdays.contains(calendar.component(.weekday, from: candidate)) {
                    return candidate
                }
            }
            return nil
        }
    }
}
