import Foundation
import FirebaseCore
import FirebaseFirestore
import GlassDoKit

/// Kullanıcının bildirdiği hatayı Firestore'daki `user_bugs` koleksiyonuna
/// tek bir belge olarak yazar.
///
/// **Neden ayrı koleksiyon:** `devices` her açılışta üzerine yazılan,
/// cihaz başına tek bir belge; hata raporu ise olay başına bir kayıt ve
/// asla ezilmemeli. İkisini aynı belgede tutmak, ikinci raporda birincisini
/// kaybetmek olurdu. `deviceID` alanı iki koleksiyonu birbirine bağlıyor:
/// bir rapora bakarken o cihazın kullanım geçmişine geçilebiliyor.
///
/// **Neden anonim:** `DeviceAnalyticsService`'le aynı cihaz kimliği
/// kullanılıyor — yerelde üretilen bir UUID. İletişim adresi yalnızca
/// kullanıcı kendi eliyle yazarsa eklenir, boş bırakılabilir.
@MainActor
enum BugReportService {
    /// Belge biçimi değiştiğinde artırılıyor. Yönetim paneli eski ve yeni
    /// raporları aynı listede gösterecek; hangi alanların var olduğunu
    /// tahmin etmek yerine bu sayıya bakabilmesi gerekiyor.
    static let schemaVersion = 1

    enum SubmissionError: LocalizedError {
        case firebaseUnavailable
        case emptyDescription
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .firebaseUnavailable:
                L10n.s(
                    "Sunucu bağlantısı kurulamadı. İnternet bağlantınızı kontrol edip yeniden deneyin.",
                    "Could not reach the server. Check your internet connection and try again.",
                    "Не удалось связаться с сервером. Проверьте подключение к интернету и попробуйте снова."
                )
            case .emptyDescription:
                L10n.s(
                    "Lütfen ne olduğunu kısaca yazın.",
                    "Please describe what happened.",
                    "Пожалуйста, опишите, что произошло."
                )
            case .writeFailed(let reason):
                L10n.s(
                    "Rapor gönderilemedi: \(reason)",
                    "Could not send the report: \(reason)",
                    "Не удалось отправить отчёт: \(reason)"
                )
            }
        }
    }

    /// Yerel Firestore kuyruğuna yazar ve belge kimliğini hemen döner.
    /// Tamamlama yalnızca sunucu yanıtından sonra çağrılır; çevrimdışıyken
    /// bu süre belirsiz olduğundan arayüz kendi bekleme durumunu yönetir.
    static func enqueue(
        area: BugArea,
        severity: BugSeverity,
        summary: String,
        details: String,
        steps: String,
        contact: String,
        diagnostics: BugDiagnostics?,
        completion: @escaping @MainActor @Sendable (String, String?) -> Void
    ) throws -> String {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetails.isEmpty else { throw SubmissionError.emptyDescription }
        guard FirebaseApp.app() != nil else { throw SubmissionError.firebaseUnavailable }

        let db = Firestore.firestore()
        // Kimlik önceden alınıyor: belge kendi kimliğini de içerebiliyor,
        // böylece dışa aktarılan bir JSON'da "bu hangi rapor" bilgisi
        // kaybolmuyor.
        let ref = db.collection("user_bugs").document()
        let reportID = ref.documentID

        var fields: [String: Any] = [
            "reportID": reportID,
            "schemaVersion": schemaVersion,
            "deviceID": DeviceAnalyticsService.deviceID,

            // Kullanıcının anlattığı kısım
            "area": area.rawValue,
            "areaTitle": area.title,
            "sourceHint": area.sourceHint,
            "severity": severity.rawValue,
            "summary": summary.trimmingCharacters(in: .whitespacesAndNewlines),
            "details": trimmedDetails,
            "steps": steps.trimmingCharacters(in: .whitespacesAndNewlines),
            "contact": contact.trimmingCharacters(in: .whitespacesAndNewlines),

            // Zaman iki biçimde: sunucu saati sıralama için tek güvenilir
            // kaynak (cihaz saati yanlış ayarlı olabilir), yerel saat ise
            // "sabah 9'da oldu" gibi kullanıcı ifadelerini doğrulamak için.
            "createdAt": FieldValue.serverTimestamp(),
            "reportedAtLocal": ISO8601DateFormatter().string(from: .now),
            "timeZone": TimeZone.current.identifier,

            // Yönetim tarafı iş akışı. Varsayılanları istemci yazıyor ki
            // panel eksik alan durumunu ayrıca ele almak zorunda kalmasın.
            "status": "new",
            "triage": [
                "priority": severity == .crash ? "high" : "normal",
                "assignee": "",
                "notes": "",
                "resolution": "",
                "duplicateOf": "",
            ],
        ]

        if let diagnostics {
            fields["diagnosticsIncluded"] = true
            fields.merge(diagnostics.firestoreFields) { current, _ in current }
        } else {
            // Kullanıcı teknik bilgi göndermeyi kapattı. Sürüm yine de
            // gerekiyor — hangi yapıda olduğu bilinmeyen bir rapor
            // neredeyse hiçbir şey anlatmıyor; bu yüzden ayrı ayrı
            // belirtiliyor ki gizlilik notu dürüst kalsın.
            fields["diagnosticsIncluded"] = false
            fields["app"] = [
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            ]
        }

        ref.setData(fields, completion: { error in
            let message = error.map { SubmissionError.writeFailed($0.localizedDescription).localizedDescription }
            _Concurrency.Task { @MainActor in completion(reportID, message) }
        })
        return reportID
    }

    /// Uygulama kapatılıp açıldıysa eski tamamlama geri çağrısı yoktur.
    /// Bekleyen yazılar sunucuda işlenince yerel belgeyi okuyarak sonucu
    /// bulur; okuma izni istemez ve bağlantı yokken beklemeye devam eder.
    static func reconcilePending(_ reportID: String) async -> Bool? {
        guard FirebaseApp.app() != nil else { return nil }
        let db = Firestore.firestore()
        do {
            try await db.waitForPendingWrites()
            let snapshot = try await db.collection("user_bugs")
                .document(reportID).getDocument(source: .cache)
            return snapshot.exists
        } catch {
            return nil
        }
    }
}
