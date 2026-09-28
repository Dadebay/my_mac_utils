import GlassDoKit
import SwiftUI

/// Tek bir ayar sayfası: başlık şeridi ve bölümün kendisi.
///
/// Ayarlar eskiden ayrı bir pencereydi ve kendi kenar çubuğu vardı. İki
/// ayrı gezinme listesi (biri ana pencerede, biri ayarlarda) bir şeyi
/// ararken nereye bakılacağını belirsizleştiriyordu — kullanıcı ölçer
/// sayfalarıyla ayar sayfaları arasında pencere değiştirmek zorundaydı.
///
/// Sayfa artık ana pencerenin sağ sütununda çiziliyor; bu görünüm de
/// pencereden bağımsız, yalnızca "hangi kategori" bilgisini alan ortak
/// gövde.
struct SettingsDetailView: View {
    let category: SettingsCategory
    let switcherController: WindowSwitcherController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                header

                switch category {
                case .general: GeneralSettingsSection()
                case .panelSize: PanelSizeSettingsSection()
                case .railIcons: RailIconsSettingsSection()
                case .menuBar: MenuBarSettingsSection()
                case .widgets: WidgetsSettingsSection()
                case .network: NetworkSettingsSection()
                case .alerts: AlertsSettingsSection()
                case .windowSwitcher: WindowSwitcherSettingsSection(controller: switcherController)
                case .about: AboutSettingsSection()
                }

                // Kısa sayfalarda ScrollView'ın önerdiği fazla yüksekliği
                // içeriğin ALTINDA yutan eleman; dış çerçeveye `maxHeight`
                // vermek başlığı ortaya doğru itiyordu.
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SettingsMetrics.contentHorizontalInset)
            .padding(.top, SettingsMetrics.contentTopInset)
            .padding(.bottom, SettingsMetrics.contentBottomInset)
            .frame(maxWidth: SettingsMetrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Bölüm değişince içerik baştan kuruluyor: eski satırların
            // (özellikle segmentli seçicilerin) yanlış ölçülmüş boyutlarını
            // miras almasınlar.
            .id(category)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SettingsCategoryIcon(category: category, size: 48, radius: Layout.Radius.large)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.app(size: 28, weight: .semibold))
                    .kerning(-0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(category.subtitle)
                    .font(.app(.titleLarge))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
