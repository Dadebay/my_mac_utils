import Foundation
import AppKit
import UserNotifications
import GlassDoKit

/// İki sistem uyarısı: Mac ısındığında ve çöp kutusu şiştiğinde bildirim.
///
/// Uygulama açılışında başlıyor, panel/pencere kapalıyken de sürüyor —
/// ikisi de kullanıcı ekrana bakmadığı anda olan şeyler.
///
/// **Neden bildirim izni açılışta istenmiyor:** `FocusSessionCoordinator`
/// ile aynı kural — izin ilk gerçek uyarı anında isteniyor. Açılışta
/// sorulan izin, kullanıcının henüz karşılığını görmediği bir şey için
/// sorulmuş oluyor ve daha sık reddediliyor.
@MainActor
final class SystemAlertService {
    static let shared = SystemAlertService()

    private init() {}

    private enum Config {
        /// Sıcaklık yoklama aralığı. 30 sn: bir ısınma dakikalar sürüyor,
        /// daha sık bakmanın ölçüme kattığı bir şey yok — üstelik yoklama
        /// kendisi de CPU harcıyor.
        static let thermalPoll: Duration = .seconds(30)
        /// Eşiği kaç ölçüm üst üste geçmeli. Tek bir sıçrama (Spotlight
        /// dizinlemesi, bir derleme) bildirimi hak etmiyor.
        static let hotSamplesNeeded = 2
        /// Aynı ısınma için tekrar bildirim atmadan önceki bekleme.
        static let thermalCooldown: TimeInterval = 15 * 60
        /// Bildirimden sonra "soğudu" saymak için eşiğin kaç derece altına
        /// inilmeli. Histerezis olmadan eşiğin tam etrafında salınan bir
        /// sıcaklık her turda yeni bildirim üretirdi.
        static let coolDownMargin: Double = 8

        /// Çöp yoklama aralığı — çöp yavaş büyür.
        static let trashPoll: Duration = .seconds(6 * 60 * 60)
        /// Aynı çöp için yeniden bildirim: bu kadar zaman geçtiyse ya da
        /// boy bu kat kadar büyüdüyse.
        static let trashRenotifyAfter: TimeInterval = 7 * 24 * 60 * 60
        static let trashGrowthFactor: Double = 1.5
    }

    private enum Identifier {
        static let thermal = "alert.thermal"
        static let trash = "alert.trash"
        static let trashCategory = "alert.trash.category"
        static let openTrashAction = "alert.trash.open"
    }

    private var thermalTask: _Concurrency.Task<Void, Never>?
    private var trashTask: _Concurrency.Task<Void, Never>?

    private var consecutiveHotSamples = 0
    private var lastThermalNotification: Date?
    /// Bildirim gönderildikten sonra sıcaklık eşiğin altına inene kadar
    /// yeni bildirim yok — `thermalCooldown` bekleme, bu ise histerezis.
    private var isInThermalAlertState = false

    // MARK: - Yaşam döngüsü

    func start() {
        registerNotificationCategories()
        restartThermalMonitor()
        restartTrashMonitor()
    }

    /// Ayarlardaki anahtar değiştiğinde çağrılıyor: kapatılan bir izleyici
    /// bir sonraki yoklamaya kadar çalışmaya devam etmesin.
    func settingsChanged() {
        restartThermalMonitor()
        restartTrashMonitor()
    }

    private func restartThermalMonitor() {
        thermalTask?.cancel()
        consecutiveHotSamples = 0
        guard SystemAlertSettings.thermalEnabled else { return }
        thermalTask = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                await self?.checkTemperature()
                try? await _Concurrency.Task.sleep(for: Config.thermalPoll)
            }
        }
    }

    private func restartTrashMonitor() {
        trashTask?.cancel()
        guard SystemAlertSettings.trashEnabled else { return }
        trashTask = _Concurrency.Task { [weak self] in
            // Açılışta hemen değil: uygulama açılışının kendi disk
            // trafiğiyle yarışmasın.
            try? await _Concurrency.Task.sleep(for: .seconds(20))
            while !_Concurrency.Task.isCancelled {
                await self?.checkTrash()
                try? await _Concurrency.Task.sleep(for: Config.trashPoll)
            }
        }
    }

    // MARK: - Isınma

    private func checkTemperature() async {
        guard SystemAlertSettings.thermalEnabled else { return }

        let threshold = SystemAlertSettings.thermalThreshold
        let temperature = CPUTemperature.current().flatMap {
            CPUTemperature.isPlausible($0) ? $0 : nil
        }
        let pressure = SystemSampler.thermalPressure()

        // Sıcaklık okunabiliyorsa asıl ölçüt o. Okunamadığında (sandbox'lı
        // yapıda IOHID sensörleri kapalı olabiliyor) sistemin kendi
        // bildirdiği termal baskı kullanılıyor — sayı yok ama "ısındı"
        // bilgisi yine doğru.
        let isHot: Bool
        if let temperature {
            isHot = temperature >= threshold
        } else {
            isHot = pressure == .serious || pressure == .critical
        }

        guard isHot else {
            // Eşiğin belirgin biçimde altına inildiyse uyarı durumu
            // kapanıyor; bir sonraki ısınma yeniden bildirim alabilir.
            if let temperature, temperature < threshold - Config.coolDownMargin {
                isInThermalAlertState = false
            } else if temperature == nil, pressure == .nominal || pressure == .fair {
                isInThermalAlertState = false
            }
            consecutiveHotSamples = 0
            return
        }

        consecutiveHotSamples += 1
        guard consecutiveHotSamples >= Config.hotSamplesNeeded else { return }
        guard !isInThermalAlertState else { return }
        if let last = lastThermalNotification,
           Date.now.timeIntervalSince(last) < Config.thermalCooldown {
            return
        }

        // Suçluyu ancak gerçekten bildirim atacakken arıyoruz: iki saniye
        // bekleyen bir ölçüm, her yoklamada yapılacak bir iş değil.
        let offenders = await TopProcessSampler.topProcesses()
        await postThermalNotification(
            temperature: temperature,
            pressure: pressure,
            offenders: offenders
        )

        lastThermalNotification = .now
        isInThermalAlertState = true
        consecutiveHotSamples = 0
    }

    private func postThermalNotification(
        temperature: Double?,
        pressure: ThermalPressure,
        offenders: [TopProcessSampler.Sample]
    ) async {
        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = temperature.map {
            L10n.s(
                "Mac ısınıyor · \(Int($0.rounded()))°C",
                "Your Mac is heating up · \(Int($0.rounded()))°C",
                "Mac нагревается · \(Int($0.rounded()))°C"
            )
        } ?? L10n.s(
            "Mac ısınıyor",
            "Your Mac is heating up",
            "Mac нагревается"
        )

        if let top = offenders.first {
            let percent = Int(top.cpuPercent.rounded())
            let others = offenders.dropFirst().map(\.name)
            var body = L10n.s(
                "En çok işlemci kullanan: \(top.name) (%\(percent)).",
                "Using the most CPU: \(top.name) (\(percent)%).",
                "Больше всего процессора использует: \(top.name) (\(percent)%)."
            )
            if !others.isEmpty {
                body += " " + L10n.s(
                    "Ardından: \(others.joined(separator: ", ")).",
                    "Then: \(others.joined(separator: ", ")).",
                    "Затем: \(others.joined(separator: ", "))."
                )
            }
            content.body = body
        } else if TopProcessSampler.canEnumerate {
            // Liste boş ama işlemler okunabiliyor: ya yük root'a ait bir
            // servisten geliyor (`proc_pid_rusage` başka kullanıcının
            // işlemini vermiyor) ya da kimse tek başına baskın değil.
            content.body = L10n.s(
                "Baskın bir işlem bulunamadı — yük bir sistem servisinden geliyor olabilir.",
                "No single process stands out — the load may come from a system service.",
                "Ни один процесс не выделяется — нагрузка может идти от системной службы."
            )
        } else {
            // İşlem listesi bu yapıda hiç okunamıyor (sandbox). "Bulunamadı"
            // demek yanlış olurdu: aranamadı.
            content.body = L10n.s(
                "Hangi uygulamanın yüklediği bu sürümde okunamıyor. Activity Monitor açıp işlemciye göre sıralayın.",
                "This build can't read which app is loading the CPU. Open Activity Monitor and sort by CPU.",
                "Эта сборка не может определить, какое приложение нагружает процессор. Откройте Мониторинг системы и отсортируйте по ЦП."
            )
        }

        if temperature == nil {
            content.body += " " + L10n.s(
                "(Sıcaklık okunamadı; sistemin termal baskısı: \(Self.pressureTitle(pressure)).)",
                "(Temperature unavailable; system thermal pressure: \(Self.pressureTitle(pressure)).)",
                "(Температура недоступна; термальное давление системы: \(Self.pressureTitle(pressure)).)"
            )
        }

        content.sound = nil
        // Isınma uyarısı sessiz: kullanıcı zaten fanı duyuyor, üstüne bir
        // de ses çalmak katkı değil rahatsızlık olurdu.
        await deliver(content, identifier: Identifier.thermal)
    }

    // MARK: - Çöp kutusu

    private func checkTrash() async {
        guard SystemAlertSettings.trashEnabled else { return }
        guard let trashURL = Self.trashURL() else { return }
        // Sandbox'lı yapıda `~/.Trash` listelenemiyor (ölçüldü): yol
        // çözülüyor ama içerik okunamıyor, boy her zaman 0 çıkar. Sessizce
        // 0 ölçüp "eşiğin altında" demek yerine hiç başlamıyoruz —
        // ayarlar sayfası da bunu kullanıcıya yazıyor.
        guard Self.isTrashReadable else { return }

        let bytes = await Self.directorySize(at: trashURL)
        let thresholdBytes = UInt64(SystemAlertSettings.trashThresholdGB * 1_000_000_000)
        guard bytes >= thresholdBytes else { return }

        // Aynı çöp için tekrar tekrar bildirim atmamak: ya bir hafta
        // geçmeli ya da çöp belirgin biçimde büyümeli. Kullanıcı "şimdi
        // değil" dediyse bu bir karar; ertesi gün aynı bildirimi görmek
        // kararın yok sayılması olurdu.
        let lastBytes = SystemAlertSettings.trashLastNotifiedBytes
        if let last = SystemAlertSettings.trashLastNotifiedAt {
            let enoughTime = Date.now.timeIntervalSince(last) >= Config.trashRenotifyAfter
            let enoughGrowth = Double(bytes) >= Double(lastBytes) * Config.trashGrowthFactor
            guard enoughTime || enoughGrowth else { return }
        }

        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.s(
            "Çöp kutusunda \(Self.formatted(bytes)) birikti",
            "\(Self.formatted(bytes)) piled up in the Trash",
            "В корзине накопилось \(Self.formatted(bytes))"
        )
        content.body = L10n.s(
            "Boşaltmak bu alanı geri kazandırır. Ne silineceğini görmek için çöp kutusunu açın.",
            "Emptying it frees that space. Open the Trash to see what would be deleted.",
            "Очистка освободит это место. Откройте корзину, чтобы увидеть, что будет удалено."
        )
        content.categoryIdentifier = Identifier.trashCategory
        content.sound = nil

        await deliver(content, identifier: Identifier.trash)
        SystemAlertSettings.trashLastNotifiedAt = .now
        SystemAlertSettings.trashLastNotifiedBytes = bytes
    }

    /// Kullanıcının ana çöp kutusu. Bağlı disklerin `.Trashes` klasörleri
    /// sayılmıyor: sandbox'ta erişilemiyorlar ve Finder da onları ayrı
    /// gösteriyor.
    static func trashURL() -> URL? {
        try? FileManager.default.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    /// Çöp kutusunun içeriği bu yapıda listelenebiliyor mu. Sandbox'ta
    /// hayır; kullanıcının bir kez klasör seçmesiyle alınan bir yer imi
    /// gerekir (bkz. `docs/17-SYSTEM-ALERTS.md`).
    /// Bu yapı App Sandbox içinde mi çalışıyor.
    ///
    /// Çöp kutusu erişiminin neden olmadığını ayırmak için gerekiyor:
    /// sandbox'ta hiçbir zaman mümkün değil, sandbox'sız yapıda ise
    /// yalnızca Tam Disk Erişimi verilmediği için yok — ikincisi
    /// kullanıcının açabileceği bir şey, birincisi değil.
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Tam Disk Erişimi ayarını açar.
    @MainActor
    static func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    static var isTrashReadable: Bool {
        guard let url = trashURL() else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// Klasörün toplam boyu. `nonisolated` ve arka planda: çöpte on binlerce
    /// dosya olabiliyor, ana aktörde gezinmek arayüzü dondururdu.
    nonisolated static func directorySize(at url: URL) async -> UInt64 {
        await _Concurrency.Task.detached(priority: .utility) {
            measureDirectory(at: url)
        }.value
    }

    /// Gezinme ayrı ve **eşzamanlı** bir fonksiyonda: `DirectoryEnumerator`'ın
    /// yineleyicisi `async` bağlamda kullanılamıyor (derleyici reddediyor).
    /// Çağıran taraf bunu zaten arka plandaki bir `Task.detached` içinde
    /// çağırıyor, yani ana aktör bloklanmıyor.
    private nonisolated static func measureDirectory(at url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.isRegularFile == true else { continue }
            // Diskte gerçekten kaplanan yer: mantıksal boyut seyrek ve
            // sıkıştırılmış dosyalarda yalan söylüyor, kullanıcı da
            // "boşaltınca ne kazanacağım" diye bakıyor.
            total &+= UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// `ThermalPressure`'ın kendi adı yok; dört görünüm aynı `switch`'i
    /// tekrarlıyor (ör. `ProcessorDashboardView.thermalText`). Paylaşılan
    /// tipi bu iş için değiştirmek yerine burada yerel bir karşılık:
    /// bildirim metni parantez içinde tek kelime istiyor.
    static func pressureTitle(_ pressure: ThermalPressure) -> String {
        switch pressure {
        case .nominal: L10n.thermalNominal
        case .fair: L10n.thermalFair
        case .serious: L10n.thermalSerious
        case .critical: L10n.thermalCritical
        }
    }

    static func formatted(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Bildirim altyapısı

    /// Çöp bildirimindeki düğme. **Silmiyor, Finder'da açıyor** — kasıtlı:
    /// geri alınamaz bir silmeyi, ne silindiğini görmeden tek tık uzağa
    /// koymak doğru değil. Üstelik sandbox'lı yapıda uygulamanın
    /// `~/.Trash`'e erişimi yok; "Boşalt" düğmesi mağaza sürümünde sessizce
    /// hiçbir şey yapmayan bir düğme olurdu.
    private func registerNotificationCategories() {
        let open = UNNotificationAction(
            identifier: Identifier.openTrashAction,
            title: L10n.s("Çöp Kutusunu Aç", "Open Trash", "Открыть корзину"),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Identifier.trashCategory,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([category])
        center.delegate = NotificationResponder.shared
    }

    private func ensureAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
        }
        return await center.notificationSettings().authorizationStatus == .authorized
    }

    private func deliver(_ content: UNMutableNotificationContent, identifier: String) async {
        // Tetikleyici yok: uyarı şu anki duruma ait, planlanmış bir şey
        // değil. Aynı kimlik bir öncekinin üstüne yazıyor — bildirim
        // merkezinde aynı uyarıdan beş tane birikmesin.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Bildirim düğmelerine verilen yanıtları karşılayan temsilci.
///
/// `@unchecked Sendable`: tipin hiç saklı durumu yok — yalnızca gelen
/// yanıtı ana aktöre aktarıyor. `UNUserNotificationCenter` temsilciyi
/// kendi kuyruğundan çağırdığı için aktöre bağlanamıyor.
private final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationResponder()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "alert.trash.open"
            || (response.actionIdentifier == UNNotificationDefaultActionIdentifier
                && response.notification.request.identifier == "alert.trash") {
            _Concurrency.Task { @MainActor in
                if let url = SystemAlertService.trashURL() {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        completionHandler()
    }

    /// Uygulama öndeyken de görünsün: ısınma uyarısı tam olarak kullanıcı
    /// bilgisayarı kullanırken anlam taşıyor.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
