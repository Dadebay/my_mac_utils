import Observation
import SwiftUI

/// Ana pencerenin dışından "şu sayfayı aç" demenin tek yolu.
///
/// Ayarlar, kenar rayındaki dişliden, menü çubuğundan ve ⌘, ile
/// açılabiliyor; üçü de görünüm ağacının dışında. Eskiden bunlar
/// SwiftUI'nin `openSettings` eylemini çağırıp ayrı bir pencere
/// açıyordu — ayarlar ana pencereye taşınınca o kapı artık ikinci bir
/// pencere değil, ana penceredeki bir sayfa seçimi olmalı.
///
/// İstek burada bir kez bırakılıyor, `ContentView` görür görmez alıp
/// tüketiyor (bkz. `consume()`). Pencere henüz açık değilken bırakılan
/// istek de kaybolmuyor: pencere kurulduğunda `onAppear` onu okuyor.
@MainActor
@Observable
final class MainWindowRouter {
    static let shared = MainWindowRouter()

    private init() {}

    /// Bekleyen sayfa isteği. Tüketilince `nil`'e dönüyor ki aynı sayfa
    /// arka arkaya istendiğinde değer değişimi yeniden tetiklensin.
    private(set) var requestedSelection: SidebarSelection?

    func show(_ selection: SidebarSelection) {
        requestedSelection = selection
    }

    /// Ayarlar her açılışta "Genel"e dönmüyor: kullanıcı çoğunlukla son
    /// baktığı ayarı bir daha kurcalamak için geliyor.
    func showSettings() {
        show(.settings(.lastViewed))
    }

    func consume() {
        requestedSelection = nil
    }
}
