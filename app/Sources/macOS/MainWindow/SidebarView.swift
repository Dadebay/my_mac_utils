import AppKit
import SwiftUI
import SwiftData
import GlassDoKit

/// `.systemDashboard` dört ölçeri birden gösterdiği için tek bir özelliğe
/// karşılık gelmiyor — kasıtlı olarak izlenmiyor.
private extension SidebarSelection {
    var usageFeature: UsageFeature? {
        switch self {
        case .list: nil
        case .systemDashboard: nil
        case .systemMonitor: .memory
        case .network: .network
        case .battery: .battery
        case .disk: .disk
        case .processor: .processor
        case .folders: .folders
        // Odak geçmişi bir ölçer sayfası değil; kullanım sayacı yok.
        case .focusHistory: nil
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSelection?

    @Query(filter: Task.activePredicate()) private var activeTasks: [Task]
    @Query(filter: Task.completedPredicate()) private var completedTasks: [Task]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(EdgePanelController.self) private var panelController

    private var tiers: ChromeTextTiers { .resolve(colorScheme) }

    private var total: Int { activeTasks.count + completedTasks.count }
    private var progress: Double {
        total == 0 ? 0 : Double(completedTasks.count) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            appHeader

            // Sistem bölümü yedi satıra çıktı; en küçük pencere boyunda
            // ilerleme özeti alttan taşmasın diye satırlar kayabiliyor.
            // Başlık ve özet sabit kalıyor: satırların yeri seçimle
            // değişmemeli.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(L10n.listsSection)

                    VStack(spacing: 3) {
                        row(.active, count: activeTasks.count)
                        row(.completed, count: completedTasks.count)
                    }
                    .padding(.horizontal, 10)

                    sectionHeader(L10n.systemSection, topPadding: 20)

                    VStack(spacing: 3) {
                        ForEach(SidebarEntry.systemEntries, id: \.selection) { entry in
                            systemRow(
                                entry.selection,
                                title: entry.title,
                                symbolName: entry.symbolName,
                                colors: entry.colors
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)

            progressFooter
        }
        .frame(minWidth: 200)
        // Zemin en altta: satırların kendi yüzeyleri bu ışığın üstünde
        // yüzüyor (bkz. `ChromeAmbience`).
        .background { ChromeAmbience(placement: .sidebar) }
    }

    private func sectionHeader(_ title: String, topPadding: CGFloat = 0) -> some View {
        Text(title)
            .font(.app(size: 10, weight: .semibold))
            .foregroundStyle(tiers.section)
            .kerning(1.0)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, topPadding)
            .padding(.bottom, 7)
    }

    /// Uygulamanın kimliği. Simge çizilmiyor, sistemin bildiği gerçek
    /// uygulama ikonu kullanılıyor: Dock'taki, Finder'daki ve buradaki
    /// aynı olmalı — elle çizilen bir kopya ikon değiştiğinde geride
    /// kalırdı.
    private var appHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .background {
                    // Simgenin arkasından sızan ışık — ortam ışığının
                    // kaynağını burada bir kez hissettiriyor.
                    Circle()
                        .fill(ChromePalette.blue.opacity(0.34))
                        .frame(width: 30, height: 30)
                        .blur(radius: 16)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("GlassDo")
                    .font(.app(size: 16, weight: .bold))
                    .foregroundStyle(tiers.primary)

                Text(L10n.appTagline)
                    .font(.app(size: 11))
                    .foregroundStyle(tiers.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private func row(_ list: SmartList, count: Int) -> some View {
        let isSelected = selection == .list(list)
        return Button {
            selection = .list(list)
            UsageStore.track(list == .active ? .tasks : .completed, source: .mainWindow)
        } label: {
            HStack(spacing: 11) {
                SidebarIconTile(symbolName: list.symbolName, colors: list.tint)

                Text(list.title)
                    .font(.app(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? tiers.selectedLabel : tiers.label)

                Spacer(minLength: 6)

                badge(count)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowButtonStyle(isSelected: isSelected))
    }

    /// Sistem satırlarının kaynağı `SidebarEntry.systemEntries`: aynı
    /// liste pencere araç çubuğundaki sayfa rozetini de besliyor. Burada
    /// ikinci bir kopya tutulunca ikisi birbirinden kaymıştı — kenar
    /// çubuğunda "İşlemci Yükü" ve ayrı bir "Batarya" satırı görünürken
    /// sayfanın kendi adı "CPU ve Pil"di.

    private func systemRow(
        _ target: SidebarSelection,
        title: String,
        symbolName: String,
        colors: [Color]
    ) -> some View {
        let isSelected = selection == target
        return Button {
            selection = target
            if let feature = target.usageFeature {
                UsageStore.track(feature, source: .mainWindow)
            }
        } label: {
            HStack(spacing: 11) {
                SidebarIconTile(symbolName: symbolName, colors: colors)

                Text(title)
                    .font(.app(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? tiers.selectedLabel : tiers.label)

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowButtonStyle(isSelected: isSelected))
    }

    /// Sayaç rozeti: kontrastı bilerek düşük. Satırın konusu ikon ve ad;
    /// sayı yalnızca göz gezdirirken fark edilmeli.
    private func badge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.app(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(tiers.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
                    }
            }
    }

    /// Kenar panelini açıp kapatan düğme.
    ///
    /// Tek yol menü çubuğundaki menüydü; menü çubuğu simgesi görünmediğinde
    /// (çentiğin arkasına düşmüş, ya da çok simgeli bir çubukta gizlenmiş)
    /// kapatılan panel bir daha açılamıyordu.
    private var panelToggle: some View {
        let isVisible = panelController.isPanelVisible
        return Button {
            panelController.togglePanelVisibility()
            if !isVisible { UsageStore.track(.panelVisibility, source: .mainWindow) }
        } label: {
            Image(systemName: isVisible ? "sidebar.right" : "rectangle.righthalf.inset.filled")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isVisible ? tiers.secondary : tiers.primary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isVisible ? L10n.hideWidget : L10n.showWidget)
        .accessibilityLabel(isVisible ? L10n.hideWidget : L10n.showWidget)
    }

    /// Kenar çubuğunun dibindeki durum alanı. Kendi kartı yok: ince bir
    /// ayraçla ayrılıp aynı ışığın üstünde duruyor — ayrı bir kutu, listeyi
    /// kesip alta yapıştırılmış gibi görünüyordu.
    private var progressFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(ChromePalette.hairline)
                .frame(height: 1)
                .padding(.bottom, 3)

            HStack(spacing: 7) {
                // Sabit bir gösterge: canlı bir ölçüme bağlı değil,
                // uygulama açıkken görünüyor.
                Circle()
                    .fill(ChromePalette.statusDot)
                    .frame(width: 6, height: 6)
                    .shadow(color: ChromePalette.statusDot.opacity(0.55), radius: 3)

                Text(L10n.sidebarSystemRunning)
                    .font(.app(size: 11))
                    .foregroundStyle(tiers.secondary)

                Spacer(minLength: 0)

                panelToggle
            }

            Text(L10n.progressSummary(completedTasks.count, total))
                .font(.app(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tiers.primary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.09))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [ChromePalette.progressStart, ChromePalette.progressEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
                        // Dolgunun kendi ışığı: çubuk bir çizgi değil,
                        // yanan bir gösterge gibi okunuyor.
                        .shadow(color: ChromePalette.progressStart.opacity(0.45), radius: 5, y: 0)
                }
            }
            .frame(height: 6)
            .animation(
                reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1.0),
                value: progress
            )
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }
}
