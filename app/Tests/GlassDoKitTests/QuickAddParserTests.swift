import Testing
import Foundation
@testable import GlassDoKit

struct QuickAddParserTests {
    /// Sabit referans "şimdi": 2024-01-08 Pazartesi, 10:00 — hafta günü ve
    /// göreli tarih testlerini belirlenebilir kılmak için.
    private var referenceNow: Date {
        var components = DateComponents()
        components.year = 2024; components.month = 1; components.day = 8
        components.hour = 10; components.minute = 0
        return Calendar.current.date(from: components)!
    }

    @Test("Yarın, saat ve öncelik birlikte ayrıştırılıyor")
    func dueDateTimeAndPriority() throws {
        let result = QuickAddParser.parse("yarın 15:00 teklif gönder !yüksek", now: referenceNow)
        #expect(result.title == "teklif gönder")
        #expect(result.priority == .high)

        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: result.dueDate!)
        #expect(components.day == 9)
        #expect(components.hour == 15)
        #expect(components.minute == 0)
    }

    @Test("Çıplak hafta günü bir sonraki oluşumu buluyor")
    func bareWeekday() throws {
        let result = QuickAddParser.parse("pazartesi rapor yaz", now: referenceNow)
        #expect(result.title == "rapor yaz")
        // Referans zaten pazartesi olduğundan bir sonraki pazartesi 7 gün sonra.
        let day = Calendar.current.component(.day, from: result.dueDate!)
        #expect(day == 15)
    }

    @Test("Etiketler # ile çıkarılıyor")
    func tagExtraction() throws {
        let result = QuickAddParser.parse("sunum hazırla #iş #önemli", now: referenceNow)
        #expect(result.title == "sunum hazırla")
        #expect(result.tagNames == ["iş", "önemli"])
    }

    @Test("Tanınmayan metin kaybolmuyor")
    func unrecognizedTextPreserved() throws {
        let result = QuickAddParser.parse("3 saat çalış", now: referenceNow)
        #expect(result.title == "3 saat çalış")
        #expect(result.dueDate == nil)
    }

    @Test("Çıplak saat, tarih verilmeden bugüne uygulanıyor")
    func bareTimeAppliesToToday() throws {
        let result = QuickAddParser.parse("15:30 toplantı", now: referenceNow)
        #expect(result.title == "toplantı")
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: result.dueDate!)
        #expect(components.day == 8)
        #expect(components.hour == 15)
        #expect(components.minute == 30)
    }
}
