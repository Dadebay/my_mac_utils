import Testing
import Foundation
@testable import GlassDoKit

struct RecurrenceEngineTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour
        return Calendar.current.date(from: components)!
    }

    @Test("Her gün kuralı bir gün ileri alıyor")
    func daily() throws {
        let rule = RecurrenceRule(frequency: .daily)
        let next = RecurrenceEngine.nextOccurrence(after: date(2024, 1, 8), rule: rule)
        #expect(Calendar.current.component(.day, from: next!) == 9)
    }

    @Test("Her hafta kuralı yedi gün ileri alıyor")
    func weekly() throws {
        let rule = RecurrenceRule(frequency: .weekly)
        let next = RecurrenceEngine.nextOccurrence(after: date(2024, 1, 8), rule: rule)
        #expect(Calendar.current.component(.day, from: next!) == 15)
    }

    @Test("Her ay kuralı ay sonu normalizasyonunu doğru yapıyor")
    func monthlyMonthEnd() throws {
        let rule = RecurrenceRule(frequency: .monthly)
        // 31 Ocak + 1 ay = Şubat'ta 31 gün yok; Calendar 2024 (artık yıl)
        // için bunu 29 Şubat'a normalize eder — crash veya geçersiz tarih yok.
        let next = RecurrenceEngine.nextOccurrence(after: date(2024, 1, 31), rule: rule)
        let components = Calendar.current.dateComponents([.month, .day], from: next!)
        #expect(components.month == 2)
        #expect(components.day == 29)
    }

    @Test("Seçili hafta günleri arasından bir sonrakini buluyor")
    func selectedWeekdays() throws {
        // 8 Ocak 2024 Pazartesi (weekday 2). Kural: Çarşamba(4) ve Cuma(6).
        let rule = RecurrenceRule(frequency: .weekdays, weekdays: [4, 6])
        let next = RecurrenceEngine.nextOccurrence(after: date(2024, 1, 8), rule: rule)
        #expect(Calendar.current.component(.day, from: next!) == 10)
        #expect(Calendar.current.component(.weekday, from: next!) == 4)
    }

    @Test("Boş hafta günü kümesi sonraki oluşum üretmiyor")
    func emptyWeekdaysProducesNil() throws {
        let rule = RecurrenceRule(frequency: .weekdays, weekdays: [])
        let next = RecurrenceEngine.nextOccurrence(after: date(2024, 1, 8), rule: rule)
        #expect(next == nil)
    }
}
