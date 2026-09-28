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
                selectionPreview
            }

            ForEach(MenuBarCategory.allCases) { category in
                categorySection(category)
            }
        }
        .task { controller.start() }
        .onDisappear { controller.stop() }
    }

    /// Seçilenlerin canlı önizlemesi.
    ///
    /// Burada eskiden "Görünen ölçer — 3" yazan bir satır vardı. Sayı,
    /// sorulan şeyin cevabı değil: kullanıcı kaç tane seçtiğini değil
    /// menü çubuğunun neye benzeyeceğini merak ediyor, üstelik üçünün
    /// hangileri olduğunu görmek için aşağıdaki galeride mavi çerçeveli
    /// karoları aramak gerekiyordu. Şerit onları gerçek çizimleriyle,
    /// menü çubuğundaki sırayla yan yana gösteriyor.
    private var selectionPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if enabled.isEmpty {
                Text(L10n.s(
                    "Hiçbir ölçer seçili değil.",
                    "No readings selected.",
                    "Показатели не выбраны."
                ))
                .font(.app(.body))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
            } else {
                HStack(spacing: 14) {
                    ForEach(enabled) { kind in
                        MenuBarItemView(kind: kind, snapshot: snapshot)
                            .frame(height: 24)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    // Menü çubuğunun kendisini andıran koyu bir şerit:
                    // ölçerler ayarların zemininde değil, gidecekleri
                    // yerde duruyormuş gibi görünsün.
                    RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                }
            }
        }
    }

    private func categorySection(_ category: MenuBarCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(category.title, systemImage: category.symbolName)
                .font(.app(.headline, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)

            // Ölçümler kendi satırlarında, sunumları yan yana. Tek bir
            // ızgaraya dizildiklerinde aynı ölçümün üç sunumu satır
            // sonunda bölünebiliyor ve üçünün altında da aynı ad
            // yazdığı için ("Toplam yük", "Toplam yük", "Toplam yük")
            // neyin neden tekrarlandığı anlaşılmıyordu.
            VStack(alignment: .leading, spacing: 14) {
                ForEach(MenuBarItemKind.readings(in: category)) { reading in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reading.title)
                            .font(.app(.caption, weight: .medium))
                            .foregroundStyle(.secondary)

                        // Uyarlanır ızgara: dar pencerede karolar alt
                        // satıra kendiliğinden sarıyor, sabit bir sütun
                        // sayısı taşmaya yol açardı.
                        LazyVGrid(
                            columns: [GridItem(
                                .adaptive(minimum: 124, maximum: 164),
                                spacing: 8,
                                alignment: .leading
                            )],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(reading.kinds) { kind in
                                tile(kind)
                            }
                        }
                    }
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
            VStack(spacing: 5) {
                MenuBarItemView(kind: kind, snapshot: snapshot)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)

                // Seçili işareti adın yanında: karonun köşesinde duran bir
                // rozet, dar karolarda ölçerin kendi çizimiyle çakışıyor.
                HStack(spacing: 3) {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    Text(kind.styleTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.app(.micro, weight: .medium))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isOn ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08),
                        lineWidth: isOn ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(
            isOn
                ? L10n.s("Menü çubuğundan çıkar", "Remove from menu bar", "Убрать из строки меню")
                : L10n.s("Menü çubuğuna ekle", "Add to menu bar", "Добавить в строку меню")
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title), \(kind.styleTitle)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func reset() {
        MenuBarSettings.reset()
        enabled = MenuBarSettings.enabledItems
    }
}
