import SwiftUI
import SwiftData
import AppKit
import GlassDoKit

@main
struct GlassDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var panelController = EdgePanelController()
    @State private var switcherController = WindowSwitcherController()
    @State private var noteController = PoppedNoteController()

    init() {
        do {
            container = try AppStore.makeContainer()
        } catch {
            fatalError("ModelContainer oluşturulamadı: \(error)")
        }
    }

    var body: some Scene {
        Window("GlassDo", id: "main") {
            RootWindowView(
                panelController: panelController,
                switcherController: switcherController,
                noteController: noteController,
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
    }
}

private struct RootWindowView: View {
    let panelController: EdgePanelController
    let switcherController: WindowSwitcherController
    let noteController: PoppedNoteController
    let container: ModelContainer
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentView()
            .environment(noteController)
            .task {
                noteController.configure(container: container)
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
                panelController.attach(container: container) {
                    EdgeShellView()
                        .environment(switcherController)
                }
                switcherController.startIfAuthorized()
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
        window.styleMask.insert(.fullSizeContentView)

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

    /// Ağ geçmişi görünüme değil uygulamanın ömrüne bağlı — panel kapalıyken
    /// de sayılmazsa "Bugün" yalnızca kullanıcının ekrana baktığı süreyi
    /// gösterirdi.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NetworkHistoryStore.shared.startSampling()

        // Menü çubuğu ölçerleri ana pencereye bağlı değil: pencere hiç
        // açılmasa da görünmeliler.
        MenuBarStatsController.shared.start()
    }

    /// Son birkaç saniyelik trafik, otuz saniyelik boşaltma aralığına
    /// takılıp kaybolmasın.
    func applicationWillTerminate(_ notification: Notification) {
        NetworkHistoryStore.shared.recordCurrentTraffic()
        NetworkHistoryStore.shared.flush()
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

        Button {
            switcherController.requestPermissionsAndStart()
        } label: {
            Label(
                switcherController.hasPermissions ? L10n.windowSwitcherReady : L10n.checkWindowSwitcherPermissions,
                systemImage: switcherController.hasPermissions ? "checkmark.shield" : "exclamationmark.shield"
            )
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

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label(L10n.quit, systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
