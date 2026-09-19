import Darwin
import Foundation
import WidgetKit

/// `GlassDoNetworkAgent` — ana uygulamadan tamamen bağımsız, `launchd`
/// tarafından oturum açılışında başlatılan ve `SMAppService` ile kayıtlı
/// bir arka plan yardımcısı.
///
/// Tek görevi: GlassDo-macOS.app kapalı olsa bile (Cmd+Q ile tam çıkış)
/// ağ trafiğini örneklemeye devam etmek. `NetworkHistoryStore`'un ana
/// uygulama içindeki kendi zamanlayıcısıyla birebir aynı mantığı
/// kullanıyor (`NetworkHistoryPersistence` — `Sources/Shared`'de,
/// ikisi arasında paylaşılıyor).
///
/// **Tek yazıcı kuralı:** Ayarlar'dan özellik kapatılırsa
/// `NetworkAgentSettings.isEnabled` `false` olur; bu süreç açılışta ve her
/// turda bunu kontrol edip kapalıysa hemen kendini sonlandırır — aksi
/// hâlde kullanıcı özelliği kapatsa bile `launchd` onu (KeepAlive nedeniyle)
/// yeniden başlatıp arka planda çalışmaya devam ederdi.
///
/// Ana thread bir `sleep()` döngüsüyle bloke **edilmiyor** — bu, aynı ana
/// kuyrukta duran SIGTERM işleyicisinin hiç çalışmamasına yol açardı.
/// Bunun yerine örnekleme bir `DispatchSourceTimer`'a bağlı, süreç
/// `dispatchMain()` ile ana kuyruğu servis ederek canlı kalıyor.
@MainActor
enum NetworkAgentMain {
    /// Ana uygulamanın kendi zamanlayıcısıyla aynı aralık — ikisinden
    /// hangisi aktifse UI birkaç saniyeden fazla gecikmeyecek.
    private static let sampleInterval: DispatchTimeInterval = .seconds(5)

    /// Widget'a taşımak da artık bu sürecin işi — ajan kayıtlıyken ana
    /// uygulama bunu yapmıyor (bkz. `NetworkHistoryStore.recordCurrentTraffic`).
    private static let widgetPublishInterval: TimeInterval = 5 * 60

    private static var timer: DispatchSourceTimer?
    private static var terminationSource: DispatchSourceSignal?
    private static var lastWidgetPublish = Date.distantPast

    static func run() -> Never {
        guard NetworkAgentSettings.isEnabled else {
            // Kullanıcı özelliği kapattı ama `launchd` `KeepAlive` nedeniyle
            // süreci yine de başlattı — hemen, sessizce çık. `launchd` bunu
            // "hızlı çöktü" sanıp tekrar tekrar denemesin diye kısa bir
            // bekleme sonrası temiz çıkış kodu ile dönüyoruz.
            Darwin.sleep(2)
            exit(0)
        }

        let persistence = NetworkHistoryPersistence()

        installTerminationHandler(persistence: persistence)

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: sampleInterval)
        source.setEventHandler {
            guard NetworkAgentSettings.isEnabled else { exit(0) }
            let now = Date()
            persistence.ingest(samples: NetworkInterfaceCounters.physicalSamples(), at: now)
            publishToWidgetIfNeeded(persistence: persistence, now: now)
        }
        source.resume()
        timer = source

        dispatchMain()
    }

    /// `DispatchSourceSignal`, ham `signal()`'ın aksine ana çalışma
    /// kuyruğuyla güvenle işlenebiliyor ve varsayılan sinyal davranışını
    /// (süreci hemen öldürmek) devre dışı bırakmak için önce
    /// `signal(SIGTERM, SIG_IGN)` gerektiriyor. Amaç: `launchd unload`/
    /// `SMAppService.unregister()` süreci durdurduğunda son 30 saniyeye
    /// kadarki (flush aralığı) örneklenmiş ama henüz diske yazılmamış
    /// trafiğin kaybolmaması.
    private static func installTerminationHandler(persistence: NetworkHistoryPersistence) {
        Darwin.signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            persistence.flush()
            exit(0)
        }
        source.resume()
        terminationSource = source
    }

    private static func publishToWidgetIfNeeded(persistence: NetworkHistoryPersistence, now: Date) {
        guard now.timeIntervalSince(lastWidgetPublish) >= widgetPublishInterval else { return }
        lastWidgetPublish = now

        var snapshot = SystemSnapshotStore.read() ?? SystemSnapshot()
        let windows = persistence.windowTotals(now: now)
        snapshot.date = now
        snapshot.network.today = windows.today
        snapshot.network.yesterday = windows.yesterday
        snapshot.network.last7Days = windows.last7
        snapshot.network.last30Days = windows.last30
        snapshot.network.dailyTotals = persistence.dailyTotals(days: 30, now: now)

        SystemSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

NetworkAgentMain.run()
