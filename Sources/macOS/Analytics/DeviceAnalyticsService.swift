import Foundation
import FirebaseCore
import FirebaseFirestore

/// Firestore'a cihaz başına tek bir belge yazar: kalıcı, anonim bir cihaz
/// kimliği, temel cihaz bilgisi ve günlük kullanım sayacı.
///
/// **Ne tutuyor:** cihaz kimliği (yerelde üretilen, kimseye kimlik
/// bildirmeyen bir UUID), model, işletim sistemi/uygulama sürümü, ülke
/// kodu (yalnızca `Locale` üzerinden — IP adresi hiç toplanmıyor), ilk/son
/// görülme zamanı, günlük açılış sayısı, hangi özelliğin (görevler, pano,
/// widget'lar vb.) ne sıklıkla kullanıldığı (bkz. `syncFeatureUsage`) —
/// bu son kısım görev başlığı/dosya adı gibi hiçbir içerik taşımıyor,
/// yalnızca "hangi özellik, kaç kez".
///
/// **Ne tutmuyor:** IP adresi, isim, e-posta, konum (GPS) — hiçbiri
/// istenmedi ve toplanmıyor. Bir gün IP gerekirse istemci tarafında
/// güvenilir şekilde alınamaz; bunun için Firestore yazmasını tetikleyen
/// bir Cloud Function gerekir (istek orada, sunucu tarafında görülür).
@MainActor
enum DeviceAnalyticsService {
    private static let deviceIDKey = "analytics.deviceID"

    /// İlk çalıştırmada üretilip `UserDefaults`'a yazılır; sonraki her
    /// açılışta aynı değeri döner — cihazı isimsiz ama tutarlı biçimde
    /// tanımlayan tek şey bu.
    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: deviceIDKey)
        return generated
    }

    /// Uygulama açılışında bir kez çağrılır. Firestore'a yazamazsa (ağ yok,
    /// kurallar reddetti vb.) sessizce vazgeçer — analitik hiçbir zaman
    /// uygulamanın asıl işlevini bloklamamalı.
    static func recordLaunch() {
        guard FirebaseApp.app() != nil else { return }
        let db = Firestore.firestore()
        let id = deviceID
        let deviceRef = db.collection("devices").document(id)

        var fields: [String: Any] = [
            "deviceID": id,
            "deviceModel": Self.deviceModel,
            "osVersion": Self.osVersion,
            "appVersion": Self.appVersion,
            "country": Locale.current.region?.identifier ?? "unknown",
            "language": Locale.current.language.languageCode?.identifier ?? "unknown",
            "lastSeen": FieldValue.serverTimestamp(),
        ]

        // `merge: true` her açılışta `firstSeen`'i de ezerdi, gerçek ilk
        // görülme zamanını kaybederdik — bu yüzden önce belge var mı diye
        // bakılıyor, alan yalnızca belge henüz yoksa ekleniyor.
        deviceRef.getDocument { snapshot, _ in
            if snapshot?.exists != true {
                fields["firstSeen"] = FieldValue.serverTimestamp()
            }
            deviceRef.setData(fields, merge: true) { error in
                if let error {
                    print("[DeviceAnalyticsService] cihaz belgesi yazılamadı: \(error)")
                }
            }
        }

        let today = Self.dayKey(for: .now)
        let usageRef = deviceRef.collection("dailyUsage").document(today)
        usageRef.setData(
            [
                "date": today,
                "launchCount": FieldValue.increment(Int64(1)),
                "lastLaunchAt": FieldValue.serverTimestamp(),
            ],
            merge: true
        ) { error in
            if let error {
                print("[DeviceAnalyticsService] günlük kullanım yazılamadı: \(error)")
            }
        }
    }

    /// Yerel `UsageStore`daki özellik kullanım sayaçlarını (tüm zamanlar +
    /// bugün) Firestore'a yansıtır. Her tıklamada değil, çağrıldığı anda
    /// (açılış/kapanış) mevcut toplamı yazar — `increment` kullanmıyor,
    /// çünkü tek doğruluk kaynağı zaten yerel store; buradan ayrıca
    /// artırmaya çalışmak iki sayacı senkron tutma sorunu yaratırdı.
    static func syncFeatureUsage() async {
        guard FirebaseApp.app() != nil else { return }
        let allTime = await UsageStore.shared.allTimeFeatureCounts()
        guard !allTime.isEmpty else { return }
        let today = await UsageStore.shared.todayFeatureCounts()

        let db = Firestore.firestore()
        let deviceRef = db.collection("devices").document(deviceID)

        deviceRef.setData(["featureUsage": allTime], merge: true) { error in
            if let error {
                print("[DeviceAnalyticsService] özellik kullanımı (tüm zamanlar) yazılamadı: \(error)")
            }
        }

        guard !today.isEmpty else { return }
        deviceRef.collection("dailyUsage").document(Self.dayKey(for: .now))
            .setData(["featureCounts": today], merge: true) { error in
                if let error {
                    print("[DeviceAnalyticsService] günlük özellik kullanımı yazılamadı: \(error)")
                }
            }
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var raw = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &raw, &size, nil, 0)
        return String(cString: raw)
    }

    private static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
