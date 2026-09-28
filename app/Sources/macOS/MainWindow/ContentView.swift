import GlassDoKit
import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarSelection? = .list(.active)
    // Kendi kenar rayımız (EdgePanel/EdgeRailView) daraltılınca ikon
    // şeridine dönüşüyor — o davranış masaüstüne yapışan widget'a özel.
    // Ana penceredeki kenar çubuğu için Apple'ın kendi uygulamalarındaki
    // (Finder, Mail, Notlar) gibi standart davranış kullanılıyor: daraltınca
    // sütun tamamen gizlenir, ikon rayına küçülmez.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.system.rawValue
    /// Açık sayfanın üst şeritte gösterilen ikinci satırı; sayfanın
    /// kendisinden geliyor (bkz. `pageSubtitle(_:)`).
    @State private var pageSubtitle: String?
    /// Pencere değiştirici ayar sayfası denetleyicisini istiyor.
    @Environment(WindowSwitcherController.self) private var switcherController
    /// Pencere dışından gelen sayfa istekleri (dişli, menü çubuğu, ⌘,).
    private let router = MainWindowRouter.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
                // Kenar çubuğu gizlenmiyor: pencerede zaten iki sütun var
                // ve gizleme düğmesi başlığın yanında sürekli duran,
                // neredeyse hiç kullanılmayan bir kontroldü.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selection {
                case .list(let smartList):
                    TaskListView(selection: smartList)
                case .systemDashboard:
                    SystemDashboardView()
                case .systemMonitor:
                    SystemMonitorView()
                case .network:
                    SystemMetricPage(metric: .network)
                case .battery:
                    SystemMetricPage(metric: .battery)
                case .disk:
                    SystemMetricPage(metric: .disk)
                case .processor:
                    SystemMetricPage(metric: .processor)
                case .folders:
                    // Klasör hiyerarşisi kalktı: Raf tek düzlemli bir yığın
                    // (bkz. `PanelShelfView`). Kenar paneliyle aynı görünüm,
                    // yalnızca geniş ölçülerle.
                    //
                    // Rafın kendi başlık şeridi var; pencerenin başlık
                    // çubuğu için ayrılan güvenli alan onun üstünde boş bir
                    // bant bırakıyordu. Trafik ışıkları kenar çubuğunun
                    // üstünde durduğu için bu sütunda o alanı boş tutmanın
                    // karşılığı yok.
                    PanelShelfView(isCompact: false)
                        .ignoresSafeArea(.container, edges: .top)
                case .focusHistory:
                    ScrollView {
                        FocusHistoryView()
                            .padding(20)
                    }
                    .navigationTitle(L10n.focusHistoryTitle)
                case .settings(let category):
                    SettingsDetailView(category: category, switcherController: switcherController)
                case nil:
                    ContentUnavailableView(L10n.selectAList, systemImage: "sidebar.left")
                }
            }
            // Sayfa değişimi yalnızca sönümlenmeyle: kaydırma ya da ölçek
            // kenar çubuğunun yanında dikkat çalardı, üstelik canlı veriyle
            // güncellenen grafiklerin kendi hareketiyle çakışırdı. Süre
            // Reduce Motion'da da aynı — burada zaten hareket yok.
            .id(selection)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: selection)
            .onPageSubtitleChange { pageSubtitle = $0 }
            // Pencere başlığı gizli: her sayfada aynı "GlassDo" yazısı üst
            // şeridi doldurup hiçbir şey söylemiyordu. Yerine sayfanın
            // kendi kimliği geçiyor.
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    // Raf kendi kimlik satırını zaten çiziyor (bkz.
                    // `PanelShelfView.titleBlock`) — buradaki rozet üst
                    // üste ikinci bir "Shelf" başlığı olurdu.
                    if let entry = selection?.entry, selection != .folders {
                        PageToolbarBadge(entry: entry, subtitle: pageSubtitle)
                    }
                }
                // Rozet bir düğme değil, "neredeyim" yazısı: araç çubuğunun
                // ortak cam zemini onu tıklanabilir bir denetim gibi
                // gösteriyordu.
                .sharedBackgroundVisibility(.hidden)

                // Sayfanın kendi eylemleri rozetin dibine yapışmasın:
                // solda neredeyim, sağda ne yapabilirim.
                ToolbarSpacer(.flexible, placement: .navigation)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme((AppTheme(rawValue: themeRaw) ?? .system).colorScheme)
        // Pencere zaten açıkken gelen istek buradan giriyor.
        .onChange(of: router.requestedSelection) { _, requested in
            applyRequestedSelection(requested)
        }
        // Pencere kapalıyken bırakılan istek `onChange`'e hiç uğramıyor:
        // istek, pencere kurulmadan önce konuyor. İlk kuruluşta burada
        // okunuyor.
        .onAppear { applyRequestedSelection(router.requestedSelection) }
        // Ayarlardan çıkılan bölüm hatırlanıyor: ayarlar bir dahaki sefere
        // buradan açılıyor (bkz. `MainWindowRouter.showSettings`).
        .onChange(of: selection) { _, new in
            if case .settings(let category) = new {
                SettingsCategory.lastViewed = category
            }
        }
    }

    private func applyRequestedSelection(_ requested: SidebarSelection?) {
        guard let requested else { return }
        selection = requested
        router.consume()
    }
}
