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
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
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

            // Kategoriler panodaki gibi ikişerli satırlarda, her satırda iki
            // kart aynı boyda. Tek sütunda altı kart alt alta dizildiğinde
            // sayfa uzuyor ve geniş pencerenin sağ yarısı boş kalıyordu.
            ForEach(Self.categoryPairs) { pair in
                SettingsColumns {
                    categorySection(pair.leading)
                } trailing: {
                    if let trailing = pair.trailing { categorySection(trailing) }
                }
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

    /// Bir satırdaki iki kategori.
    private struct CategoryPair: Identifiable {
        let leading: MenuBarCategory
        let trailing: MenuBarCategory?
        var id: String { leading.id }
    }

    /// Kategoriler bildirim sırasında, ikişer ikişer.
    private static var categoryPairs: [CategoryPair] {
        let all = MenuBarCategory.allCases
        return stride(from: 0, to: all.count, by: 2).map { index in
            CategoryPair(
                leading: all[index],
                trailing: index + 1 < all.count ? all[index + 1] : nil
            )
        }
    }

    /// Ölçüm adının sütunu. Sabit: bütün satırlarda karolar aynı dikey
    /// çizgide başlasın, göz satırdan satıra aynı yere insin.
    private static let readingLabelWidth: CGFloat = 100
    /// Karonun genişliği. Sabit: "392,71 GB" gibi en uzun değer de sığıyor,
    /// ve yan yana duran karolar aynı boyda olunca biçim farkı (çubuk mu
    /// yüzde mi) tek fark olarak kalıyor. İki sütunlu düzende bir kartın
    /// içine ad ve üç karo yan yana sığacak kadar dar.
    private static let tileWidth: CGFloat = 104

    /// Bir kategori: panodaki kartlarla aynı kart, içinde ölçüm satırları.
    /// Her ölçüm tek satır — ad solda, sunumları sağında yan yana.
    private func categorySection(_ category: MenuBarCategory) -> some View {
        let readings = MenuBarItemKind.readings(in: category)

        return SettingsCard(title: category.title) {
            ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                if index > 0 {
                    SettingsRowDivider()
                }
                readingRow(reading)
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
                .foregroundStyle(isOn ? AnyShapeStyle(Color.appAccent) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(width: Self.tileWidth)
            .background {
                RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                    .fill(isOn ? Color.appAccent.opacity(0.12) : Color.primary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isOn ? Color.appAccent.opacity(0.85) : Color.primary.opacity(0.08),
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
