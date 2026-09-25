import SwiftUI
import SwiftData
import AppKit
import GlassDoKit
import FirebaseCore

@main
struct GlassDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var panelController = EdgePanelController()
    @State private var switcherController = WindowSwitcherController()

    init() {
        // Her şeyden önce: bu ikinci bir kopyaysa buradan geri dönmüyor.
        // Veri deposu bir satır sonra açılıyor; ikinci kopyanın ona
        // dokunmaması gerekiyor (bkz. `SingleInstanceGuard`).
        SingleInstanceGuard.enforce()

        FirebaseApp.configure()
        do {
            container = try AppStore.makeContainer()
        } catch {
            fatalError("ModelContainer oluşturulamadı: \(error)")
        }
        // Yapışkan notlar artık ana listenin kopyası; ayrı not döneminde
        // notlara yazılmış satırlar bir kez ana listeye taşınıyor.
        StickyNoteMerge.runIfNeeded(in: container.mainContext)
    }

    var body: some Scene {
        Window("GlassDo", id: "main") {
            RootWindowView(
                panelController: panelController,
                switcherController: switcherController,
                container: container
            )
            .frame(minWidth: 780, minHeight: 480)
        }
        .modelContainer(container)

        MenuBarExtra("GlassDo", systemImage: "checklist") {
            MenuBarContentView(panelController: panelController, switcherController: switcherController)
        }

        Settings {
            SettingsView(switcherController: switcherController)
                .background(SettingsWindowChromeConfigurator())
        }
        // İçerik yalnızca en küçük ölçüyü dayatsın; kullanıcı pencereyi
        // istediği kadar büyütebilsin.
        .windowResizability(.contentMinSize)

        // Tekil pencere: aynı `id` ile ikinci kez açılmaya çalışılırsa
        // AppKit yeni bir örnek yaratmıyor, var olanı öne getiriyor —
        // ayrı bir "zaten açık mı" denetimi gerekmiyor.
        Window(L10n.s("GlassDo Hakkında", "About GlassDo", "О GlassDo"), id: "about") {
            AboutGlassDoView()
                .frame(minWidth: 600, idealWidth: 660, minHeight: 560, idealHeight: 720)
        }
        .windowResizability(.contentMinSize)

        // Hata bildirimi de tekil bir pencere: kullanıcı menüden iki kez
        // seçerse yarım dolu formu ikinci bir boş pencereyle değiştirmek
        // yazdıklarını kaybettirirdi.
        Window(L10n.s("Hata Bildir", "Report a Bug", "Сообщить об ошибке"), id: "bug-report") {
            BugReportView(panelController: panelController)
        }
        // Dialog gibi davranıyor: boyu içeriğe kilitli, kullanıcı
        // yeniden boyutlandıramıyor. Serbest boyutlu bir pencerede
        // dört alanlık bir form ya çok geniş ya çok dar duruyordu.
        .windowResizability(.contentSize)
    }
}

private struct RootWindowView: View {
    let panelController: EdgePanelController
    let switcherController: WindowSwitcherController
    let container: ModelContainer
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// Yalnızca daha önce hiç sorulmadıysa `true` olur — reddedilmiş bir
    /// seçim bir daha sorulmaz, yalnızca Ayarlar'dan değiştirilebilir.
    @State private var showingAnalyticsPrompt = !AnalyticsConsent.hasBeenAsked
    /// Analytics sayfası kapanana kadar gösterilmez — aynı anda iki sheet
    /// açılmaya çalışılmasın diye (bkz. `.task` içindeki sıralama).
    @State private var showingWorkspaceOnboarding = false

    var body: some View {
        ContentView()
            .environment(StickyNotesController.shared)
            .environment(panelController)
            .sheet(isPresented: $showingAnalyticsPrompt) {
                AnalyticsConsentPromptView { granted in
                    AnalyticsConsent.setGranted(granted)
                    if granted {
                        DeviceAnalyticsService.recordLaunch()
                        _Concurrency.Task { await DeviceAnalyticsService.syncFeatureUsage() }
                    }
                    showingAnalyticsPrompt = false
                    presentWorkspaceOnboardingIfNeeded()
                }
            }
            .sheet(isPresented: $showingWorkspaceOnboarding) {
                WorkspaceOnboardingSheet {
                    WorkspaceOnboarding.markShown()
                    showingWorkspaceOnboarding = false
                }
            }
            .task {
                // Analytics sayfası zaten yanıtlanmışsa (yeni sorulmuyor)
                // çalışma alanı seçimi doğrudan burada teklif edilir;
                // aksi hâlde analytics kapandıktan sonra yukarıdaki
                // callback'te tetiklenir — aynı anda iki sheet çakışmasın.
                if !showingAnalyticsPrompt {
                    presentWorkspaceOnboardingIfNeeded()
                }
                StickyNotesController.shared.configure(container: container)
                panelController.openMainWindow = {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                panelController.openSettings = {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                MenuBarStatsController.shared.openSettings = {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                MenuBarStatsController.shared.openMainWindow = {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                switcherController.openSettings = {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                panelController.attach(container: container) {
                    EdgeShellView()
                        .environment(switcherController)
                }
                switcherController.startIfAuthorized()
            }
    }

    /// Analytics sayfası kapanır kapanmaz aynısını açmak SwiftUI'da bazen
    /// önceki sheet'in kapanma animasyonuyla çakışıyor; kısa bir gecikme
    /// ikisinin üst üste binmesini önlüyor.
    private func presentWorkspaceOnboardingIfNeeded() {
        guard WorkspaceOnboarding.shouldShow else { return }
        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .milliseconds(350))
            guard WorkspaceOnboarding.shouldShow else { return }
            showingWorkspaceOnboarding = true
        }
    }
}

/// Ayarlar penceresinin native başlık metnini gizler ve içerik alanını
/// başlık çubuğunun altına kadar uzatır — kenar çubuğu malzemesi böylece
/// pencerenin en üst kenarına kesintisiz ulaşabiliyor. Trafik ışıkları
/// native kalıyor, yalnızca arkalarındaki opak şerit kaldırılıyor.
///
/// Yalnızca Ayarlar penceresini etkiler: bu görünüm yalnızca
/// `SettingsView`'ın kendi ağacına ekleniyor — ana pencere, kenar paneli
/// ve pencere değiştirici bu ağaçta değil, dolayısıyla dokunulmuyor.
private struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView(frame: .zero)
        probe.translatesAutoresizingMaskIntoConstraints = false
        // Pencereye ilk bağlandığı anda henüz `probe.window` kurulu
        // olmayabilir; bir sonraki run loop turunda kesin var.
        DispatchQueue.main.async { [weak probe] in
            configure(probe?.window)
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
    }

    /// Aynı pencereye tekrar tekrar çağrılsa da zararsız: hepsi durum
    /// değiştirmeyen doğrudan atama, açma/kapama gibi bir yan etkisi yok.
    private func configure(_ window: NSWindow?) {
        guard let window, window.styleMask.contains(.titled) else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // SwiftUI'ın `Settings` sahnesi pencereyi küçültme/büyütme
        // düğmeleri olmadan, `.windowResizability(.contentMinSize)`e rağmen
        // sabit boyutlu kuruyor — trafik ışıklarındaki sarı/yeşil düğmeler
        // pasif görünüyordu. Bu iki bit eksikti, geri kalanı zaten SwiftUI
        // tarafından yönetiliyor.
        window.styleMask.insert([.fullSizeContentView, .resizable, .miniaturizable])

        // Ayarlar kendi sabit HSplitView kenar çubuğunu kullanıyor; başlık
        // çubuğunda trafik ışıkları dışında ek bir araç yok.
        window.toolbar = nil
        // Görsel başlık gizli ama pencere kimliği VoiceOver ve pencere
        // menüsü (Cmd+`) için "Settings" olarak kalmalı.
        window.title = L10n.settingsTitle
    }
}

/// Ana pencere kapatılınca uygulamanın (ve dolayısıyla kenar paneli
/// widget'ının) sonlanmasını engeller — panel, pencere kapansa da ekran
/// kenarında yapışık kalmaya devam etsin diye.
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock'taki "Çık" ve ⌘Q uygulamayı kapatmıyor, arka plana alıyor —
    /// menü çubuğu ölçerleri ve widget'lar yaşamaya devam etsin diye
    /// (bkz. `AppQuit`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppQuit.shouldTerminate() { return .terminateNow }
        AppQuit.moveToBackground()
        return .terminateCancel
    }

    /// Arka plandayken Dock simgesi yok; ana pencere menü çubuğundan
    /// açıldığında simge geri geliyor.
    private var windowObserver: NSObjectProtocol?

    /// Ağ geçmişi görünüme değil uygulamanın ömrüne bağlı — panel kapalıyken
    /// de sayılmazsa "Bugün" yalnızca kullanıcının ekrana baktığı süreyi
    /// gösterirdi.
    func applicationDidFinishLaunching(_ notification: Notification) {
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { AppQuit.restoreDockIconIfNeeded(for: window) }
        }

        NetworkHistoryStore.shared.startSampling()

        // Menü çubuğu ölçerleri ana pencereye bağlı değil: pencere hiç
        // açılmasa da görünmeliler.
        MenuBarStatsController.shared.start()

        // Isınma ve çöp uyarıları da pencereye bağlı değil: ikisi de
        // kullanıcı ekrana bakmadığı anda olan şeyler.
        SystemAlertService.shared.start()

        // Pano geçmişi de panel kapalıyken kopyalanan şeyi kaçırmamalı.
        ClipboardHistoryStore.shared.startMonitoring()
        ScreenshotShelfWatcher.shared.syncWithSetting()

        if PanelSettings.contextAwareRailEnabled {
            ActiveApplicationMonitor.shared.start()
        }

        // Disk sayfasındaki "en büyük öğeler" taraması ana klasörü ve
        // /Applications'ı geziyor; sayfa açıldığında başlatılınca kullanıcı
        // boş bir listeye bakarak bekliyordu. Açılıştan birkaç saniye sonra
        // arka planda başlıyor: açılışın kendi disk trafiğiyle yarışmasın,
        // ama sayfaya gidildiğinde sonuç çoktan hazır olsun.
        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .seconds(3))
            DiskSpaceAnalyzer.shared.scanIfNeeded()
        }

        // Geçen oturumda masaüstünde bırakılan ölçerler geri geliyor.
        DesktopWidgetController.shared.restore()

        // İlk açılışta izin ekranı henüz gösterilmedi — o zaman kaydı
        // kullanıcı seçimini yaptığı an `RootWindowView` kendisi tetikler.
        // Sonraki her açılışta izin zaten "evet" ise burada devam eder.
        if AnalyticsConsent.isGranted {
            DeviceAnalyticsService.recordLaunch()
            _Concurrency.Task { await DeviceAnalyticsService.syncFeatureUsage() }
        }
    }

    /// Son birkaç saniyelik trafik, otuz saniyelik boşaltma aralığına
    /// takılıp kaybolmasın. Özellik kullanım senkronu da aynı sebeple
    /// burada tekrarlanıyor — bir sonraki açılışa kadar beklerse o
    /// oturumdaki son tıklamalar admin panelde eksik görünürdü. (En iyi
    /// çaba: süreç bu isteğin ağ üzerinden tamamlanmasını beklemeden
    /// sonlanabilir; asıl doğruluk kaynağı bir sonraki açılıştaki senkron.)
    func applicationWillTerminate(_ notification: Notification) {
        NetworkHistoryStore.shared.recordCurrentTraffic()
        NetworkHistoryStore.shared.flush()

        if AnalyticsConsent.isGranted {
            _Concurrency.Task { await DeviceAnalyticsService.syncFeatureUsage() }
        }
    }
}

/// Menü çubuğu menüsü. Her satır bir simgeyle etiketleniyor ve maddeler
/// anlam gruplarına ayrılıyor — düz metin listesi yerine sistem
/// uygulamalarının menülerine benzeyen bir düzen.
private struct MenuBarContentView: View {
    let panelController: EdgePanelController
    let switcherController: WindowSwitcherController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Panel
        Button {
            // Yalnızca gösterme anı bir "kullanım" — gizlemek yeni bir
            // etkileşim başlatmıyor, var olanı sonlandırıyor.
            let willShow = !panelController.isPanelVisible
            panelController.togglePanelVisibility()
            if willShow { UsageStore.track(.panelVisibility, source: .menuBar) }
        } label: {
            Label(
                panelController.isPanelVisible ? L10n.hideWidget : L10n.showWidget,
                systemImage: panelController.isPanelVisible ? "eye.slash" : "eye"
            )
        }

        Button {
            panelController.setMode(panelController.mode == .pinned ? .rail : .pinned)
            UsageStore.track(.pinMode, source: .menuBar)
        } label: {
            Label(
                panelController.mode == .pinned ? L10n.unpinPanel : L10n.pinPanel,
                systemImage: panelController.mode == .pinned ? "pin.slash" : "pin"
            )
        }

        Divider()

        // Pencereler
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        } label: {
            Label(L10n.mainWindow, systemImage: "macwindow")
        }

        Button {
            switcherController.toggleSummon()
        } label: {
            Label(L10n.s("Pencere Değiştirici", "Window Switcher", "Переключатель окон"), systemImage: "rectangle.on.rectangle")
        }

        Divider()

        // Uygulama
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label(L10n.settingsTitle, systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "about")
        } label: {
            Label(L10n.s("GlassDo Hakkında", "About GlassDo", "О GlassDo"), systemImage: "info.circle")
        }

        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "bug-report")
        } label: {
            Label(L10n.s("Hata Bildir…", "Report a Bug…", "Сообщить об ошибке…"), systemImage: "ladybug")
        }

        Divider()

        Button {
            AppQuit.terminate()
        } label: {
            Label(L10n.quit, systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
