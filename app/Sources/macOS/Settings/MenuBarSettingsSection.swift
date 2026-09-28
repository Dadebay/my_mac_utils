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

    /// Ölçüm adının sütunu. Sabit: bütün satırlarda karolar aynı dikey
    /// çizgide başlasın, göz satırdan satıra aynı yere insin.
    private static let readingLabelWidth: CGFloat = 116
    /// Karonun genişliği. Sabit: "392,71 GB" gibi en uzun değer de sığıyor,
    /// ve yan yana duran karolar aynı boyda olunca biçim farkı (çubuk mu
    /// yüzde mi) tek fark olarak kalıyor.
    private static let tileWidth: CGFloat = 112

    /// Bir kategori: başlık ve altında tek bir kart içinde ölçüm satırları.
    ///
    /// Bir önceki denemede her ölçümün adı karolarının üstünde ayrı bir
    /// satırdaydı. Gruplama doğruydu ama sayfa iki katına uzadı ve tek
    /// karolu ölçümler (Çekirdekler, Takas, Baskı) koca bir satırda tek
    /// başına durup sayfanın sağ yarısını boş bıraktı. Ad artık karoların
    /// solunda: her ölçüm tek satır, Sistem Ayarları'ndaki satırlar gibi.
    private func categorySection(_ category: MenuBarCategory) -> some View {
        let readings = MenuBarItemKind.readings(in: category)

        return VStack(alignment: .leading, spacing: 8) {
            Label(category.title, systemImage: category.symbolName)
                .font(.app(.headline, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                    if index > 0 {
                        Divider().overlay(Color.primary.opacity(0.06))
                    }
                    readingRow(reading)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: Layout.Radius.large, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: Layout.Radius.large, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    }
            }
        }
    }

    private func readingRow(_ reading: MenuBarReading) -> some View {
        // Yan yana sığmıyorsa (dar pencere, dört sunumlu bir ölçüm) ad
        // üste çıkıyor ve karolar sarıyor. Karolar ve ad sütunu sabit
        // genişlikte olduğu için ilk düzenin ne kadar yer istediği
        // ölçülebiliyor — `ViewThatFits` ancak öyle doğru karar veriyor.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                readingTitle(reading)
                    .frame(width: Self.readingLabelWidth, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(reading.kinds) { kind in
                        tile(kind)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                readingTitle(reading)
                LazyVGrid(
                    columns: [GridItem(
                        .adaptive(minimum: Self.tileWidth, maximum: Self.tileWidth),
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func readingTitle(_ reading: MenuBarReading) -> some View {
        Text(reading.title)
            .font(.app(.bodyLarge, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func tile(_ kind: MenuBarItemKind) -> some View {
        let isOn = enabled.contains(kind)

        return Button {
            MenuBarSettings.toggle(kind)
            enabled = MenuBarSettings.enabledItems
        } label: {
            VStack(spacing: 4) {
                MenuBarItemView(kind: kind, snapshot: snapshot)
                    .frame(height: 26)
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
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(width: Self.tileWidth)
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
