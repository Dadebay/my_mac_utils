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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sidebarHidden: Bool { columnVisibility == .detailOnly }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
                // Sistemin kendi kenar çubuğu düğmesi bizimkiyle yan yana
                // düşüyordu; tek düğme kalsın diye kaldırıldı.
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
                    PanelFolderShelfView(isCompact: false)
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
            // Düğme, dar sütunda trafik ışıklarıyla çakışmasın diye
            // ayrıntı sütununun başlangıcında duruyor.
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(
                            reduceMotion
                                ? nil
                                : .spring(response: 0.34, dampingFraction: 1.0)
                        ) {
                            columnVisibility = sidebarHidden ? .all : .detailOnly
                        }
                    } label: {
                        Image(systemName: sidebarHidden ? "sidebar.left" : "sidebar.leading")
                    }
                    .help(sidebarHidden ? L10n.expandSidebar : L10n.collapseSidebar)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme((AppTheme(rawValue: themeRaw) ?? .system).colorScheme)
    }
}
