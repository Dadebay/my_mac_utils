import Foundation

/// Sistem uyarılarının açık/kapalı durumu ve eşikleri.
///
/// `PanelSettings` gibi doğrudan `UserDefaults`'a yazıyor: uyarılar bir
/// pencereye değil uygulamanın ömrüne bağlı, bir görünümün `@State`'inde
/// yaşayamazlar.
///
/// Varsayılanlar: ikisi de **açık**. Bir uyarı ancak zamanında geldiğinde
/// işe yarıyor; kullanıcı Mac'in ısındığını zaten fark ettikten sonra
/// ayarlardan açacağı bildirimin değeri yok.
@MainActor
enum SystemAlertSettings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let thermalEnabled = "alerts.thermal.enabled"
        static let thermalThreshold = "alerts.thermal.thresholdCelsius"
        static let trashEnabled = "alerts.trash.enabled"
        static let trashThreshold = "alerts.trash.thresholdGB"
        static let trashLastNotifiedAt = "alerts.trash.lastNotifiedAt"
        static let trashLastNotifiedBytes = "alerts.trash.lastNotifiedBytes"
    }

    static var thermalEnabled: Bool {
        get { defaults.object(forKey: Key.thermalEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.thermalEnabled) }
    }

    /// °C. 85 seçildi çünkü Apple Silicon'da yoğun iş yükünde 70-80 °C
    /// normal çalışma aralığı — eşiği oraya koymak her derlemede bildirim
    /// yağdırırdı. 85 üstü artık "fan tam devirde" bölgesi.
    static var thermalThreshold: Double {
        get { defaults.object(forKey: Key.thermalThreshold) as? Double ?? 85 }
        set { defaults.set(newValue.clampedValue(60, 100), forKey: Key.thermalThreshold) }
    }

    static var trashEnabled: Bool {
        get { defaults.object(forKey: Key.trashEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.trashEnabled) }
    }

    /// GB (10⁹ bayt) — Finder da çöpün boyunu bu ölçekle gösteriyor.
    static var trashThresholdGB: Double {
        get { defaults.object(forKey: Key.trashThreshold) as? Double ?? 5 }
        set { defaults.set(newValue.clampedValue(1, 100), forKey: Key.trashThreshold) }
    }

    /// Aynı çöp için her gün bildirim atmamak adına son bildirimin zamanı
    /// ve o anki boy saklanıyor — kural `SystemAlertService`'te.
    static var trashLastNotifiedAt: Date? {
        get { defaults.object(forKey: Key.trashLastNotifiedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.trashLastNotifiedAt) }
    }

    static var trashLastNotifiedBytes: UInt64 {
        get { UInt64(max(defaults.double(forKey: Key.trashLastNotifiedBytes), 0)) }
        set { defaults.set(Double(newValue), forKey: Key.trashLastNotifiedBytes) }
    }
}

private extension Double {
    func clampedValue(_ lower: Double, _ upper: Double) -> Double {
        min(max(self, lower), upper)
    }
}
