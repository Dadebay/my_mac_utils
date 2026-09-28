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

    /// Ayar sayfaları metin sütunu genişliğinde duruyor; kullanım sayfası
    /// pano olduğu için daha geniş (bkz. `SettingsMetrics`).
    private var contentMaxWidth: CGFloat {
        switch category {
        case .about: SettingsMetrics.wideContentMaxWidth
        default: SettingsMetrics.contentMaxWidth
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
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
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Bölüm değişince içerik baştan kuruluyor: eski satırların
            // (özellikle segmentli seçicilerin) yanlış ölçülmüş boyutlarını
            // miras almasınlar.
            .id(category)
        }
        // Sayfa kimliği üst şeritteki rozette: başlık, simge ve alt
        // başlık orada duruyor. Sayfanın kendi içinde ikinci bir başlık
        // bloğu varken ekranda aynı ad iki kez, biri diğerinin hemen
        // altında yazıyordu.
        .pageSubtitle(category.subtitle)
    }
}
