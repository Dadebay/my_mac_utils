import SwiftUI
import GlassDoKit

/// Menü çubuğu ölçerlerinin galerisi.
///
/// Her karo ölçerin **gerçek** çizimini gösteriyor, temsilî bir ikonu
/// değil: menü çubuğunda ne göreceğini seçmeden önce görmek gerekiyor.
/// Karolar canlı — ekrandaki sayılar o anki ölçüm.
struct MenuBarSettingsSection: View {
    private let controller = SystemStatsController.shared
    @State private var enabled = MenuBarSettings.enabledItems

    private var snapshot: SystemSnapshot {
        SystemSnapshot(
            date: Date(),
            cpu: controller.cpu,
            memory: controller.memory,
            disk: controller.disk,
            battery: controller.battery,
            network: controller.network,
            device: controller.device,
            language: L10n.language.rawValue
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: L10n.s("Menü çubuğu", "Menu bar", "Строка меню"),
                subtitle: L10n.s(
                    "Seçtiğin ölçerler menü çubuğunda görünür. Tıklayınca ayrıntılı kart açılır.",
                    "Selected readings appear in the menu bar. Click one to open its full card.",
                    "Выбранные показатели появятся в строке меню. Нажмите, чтобы открыть карточку."
                ),
                trailing: AnyView(ResetButton { reset() })
            ) {
                HStack(spacing: 8) {
                    Text(L10n.s("Görünen ölçer", "Visible readings", "Показателей"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("\(enabled.count)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
            }

            ForEach(MenuBarCategory.allCases) { category in
                categorySection(category)
            }
        }
        .task { controller.start() }
        .onDisappear { controller.stop() }
    }

    private func categorySection(_ category: MenuBarCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(category.title, systemImage: category.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 12
            ) {
                ForEach(MenuBarItemKind.items(in: category)) { kind in
                    tile(kind)
                }
            }
        }
    }

    private func tile(_ kind: MenuBarItemKind) -> some View {
        let isOn = enabled.contains(kind)

        return Button {
            MenuBarSettings.toggle(kind)
            enabled = MenuBarSettings.enabledItems
        } label: {
            VStack(spacing: 6) {
                MenuBarItemView(kind: kind, snapshot: snapshot)
                    .frame(height: 34)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(isOn ? 0.10 : 0.045))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                isOn ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08),
                                lineWidth: isOn ? 1.5 : 1
                            )
                    }

                Text(kind.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .buttonStyle(.plain)
        .help(
            isOn
                ? L10n.s("Menü çubuğundan çıkar", "Remove from menu bar", "Убрать из строки меню")
                : L10n.s("Menü çubuğuna ekle", "Add to menu bar", "Добавить в строку меню")
        )
    }

    private func reset() {
        MenuBarSettings.reset()
        enabled = MenuBarSettings.enabledItems
    }
}
