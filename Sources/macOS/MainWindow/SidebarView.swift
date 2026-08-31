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
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSelection?

    @Query(filter: Task.activePredicate()) private var activeTasks: [Task]
    @Query(filter: Task.completedPredicate()) private var completedTasks: [Task]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                    VStack(spacing: 2) {
                        row(.active, count: activeTasks.count)
                        row(.completed, count: completedTasks.count)
                    }
                    .padding(.horizontal, 8)

                    sectionHeader(L10n.systemSection, topPadding: 16)

                    VStack(spacing: 2) {
                        ForEach(Self.systemEntries, id: \.selection) { entry in
                            systemRow(
                                entry.selection,
                                title: entry.title,
                                symbolName: entry.symbolName,
                                colors: entry.colors
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            progressFooter
        }
        .frame(minWidth: 200)
    }

    private func sectionHeader(_ title: String, topPadding: CGFloat = 0) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .kerning(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, topPadding)
            .padding(.bottom, 5)
    }

    private var appHeader: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "checklist")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.bottom, 1.5)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
            Text("GlassDo")
                .font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private func row(_ list: SmartList, count: Int) -> some View {
        let isSelected = selection == .list(list)
        return Button {
            selection = .list(list)
            UsageStore.track(list == .active ? .tasks : .completed, source: .mainWindow)
        } label: {
            HStack(spacing: 10) {
                iconTile(list, size: 22, cornerRadius: 6, glyphSize: 11)

                Text(list.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                Spacer(minLength: 6)

                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            isSelected
                                ? Color.accentColor.opacity(0.16)
                                : Color.primary.opacity(0.055)
                        )
                    )
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarHoverButtonStyle(isSelected: isSelected, cornerRadius: 8))
    }

    /// Sistem bölümünün satırları. Sıra kasıtlı: önce bütünü gösteren
    /// pano, sonra tek tek ölçerler (bellek, ağ, batarya, disk, işlemci),
    /// en sonda dosya alanı — ölçüm olmayan tek girdi olduğu için sonda.
    ///
    /// Renkler birbirinden ayrışıyor: kenar çubuğunda satırlar simgeden
    /// önce renkle tanınıyor, iki komşu satırın aynı tonu olması onları
    /// birbirine karıştırır.
    private struct SystemEntry {
        let selection: SidebarSelection
        let title: String
        let symbolName: String
        let colors: [Color]
    }

    private static var systemEntries: [SystemEntry] {
        [
            SystemEntry(
                selection: .systemDashboard,
                title: L10n.systemOverviewTitle,
                symbolName: "gauge.with.dots.needle.67percent",
                colors: [Color(red: 0.36, green: 0.64, blue: 0.98), Color(red: 0.20, green: 0.44, blue: 0.88)]
            ),
            SystemEntry(
                selection: .systemMonitor,
                title: L10n.systemMonitorTitle,
                symbolName: "memorychip",
                colors: [Color(red: 0.95, green: 0.42, blue: 0.34), Color(red: 0.82, green: 0.22, blue: 0.18)]
            ),
            SystemEntry(
                selection: .network,
                title: L10n.networkActivityLabel,
                symbolName: "globe",
                colors: [Color(red: 0.24, green: 0.78, blue: 0.74), Color(red: 0.10, green: 0.56, blue: 0.56)]
            ),
            SystemEntry(
                selection: .battery,
                title: L10n.batteryLabel,
                symbolName: "battery.100percent",
                colors: [Color(red: 0.36, green: 0.80, blue: 0.44), Color(red: 0.18, green: 0.62, blue: 0.30)]
            ),
            SystemEntry(
                selection: .disk,
                title: L10n.diskLabel,
                symbolName: "internaldrive",
                colors: [Color(red: 1.0, green: 0.68, blue: 0.28), Color(red: 0.90, green: 0.46, blue: 0.12)]
            ),
            SystemEntry(
                selection: .processor,
                title: L10n.processorLoadLabel,
                symbolName: "cpu",
                colors: [Color(red: 0.64, green: 0.44, blue: 0.98), Color(red: 0.44, green: 0.24, blue: 0.86)]
            ),
            SystemEntry(
                selection: .folders,
                title: L10n.folders,
                symbolName: "folder",
                colors: [Color(red: 0.56, green: 0.61, blue: 0.72), Color(red: 0.36, green: 0.41, blue: 0.52)]
            ),
        ]
    }

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
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.bottom, 1.5)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    }

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarHoverButtonStyle(isSelected: isSelected, cornerRadius: 8))
    }

    private func iconTile(
        _ list: SmartList, size: CGFloat, cornerRadius: CGFloat, glyphSize: CGFloat
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: list.tint, startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: list.symbolName)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 1.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
    }

    private var progressFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider().overlay(Color.white.opacity(0.07))
                .padding(.bottom, 4)

            Text(L10n.progressSummary(completedTasks.count, total))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                        .frame(width: max(geo.size.width * progress, progress > 0 ? 4 : 0))
                }
            }
            .frame(height: 5)
            .animation(
                reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1.0),
                value: progress
            )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}

/// Sidebar satırları için seçim zeminiyle aynı yerde, üzerine gelince de
/// hafif bir vurgu gösteren ortak buton stili.
private struct SidebarHoverButtonStyle: ButtonStyle {
    let isSelected: Bool
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        SidebarHoverButtonBody(configuration: configuration, isSelected: isSelected, cornerRadius: cornerRadius)
    }

    private struct SidebarHoverButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        let cornerRadius: CGFloat

        @State private var isHovering = false

        private var fill: Color {
            if isSelected { return Color.accentColor.opacity(0.13) }
            if isHovering { return Color.primary.opacity(0.045) }
            return .clear
        }

        private var borderColor: Color {
            isSelected ? Color.accentColor.opacity(0.18) : .clear
        }

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                }
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0),
                    value: isSelected
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { isHovering = $0 }
        }
    }
}
