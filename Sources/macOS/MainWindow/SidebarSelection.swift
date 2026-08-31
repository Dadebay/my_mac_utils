import Foundation

/// Kenar çubuğunun seçebileceği her şey: bir görev listesi ya da "Sistem"
/// bölümündeki girdiler. `SmartList` yalnızca görev filtrelerini temsil
/// ettiği için sistem ekranlarını da içine katmak yerine ayrı bir üst tür
/// kullanılıyor.
enum SidebarSelection: Hashable {
    case list(SmartList)
    /// Ağ, batarya, disk ve işlemciyi toplayan kart panosu.
    case systemDashboard
    /// Bellek dökümü ve çalışan uygulama listesi.
    case systemMonitor
    /// Kenar rayındaki ölçer sayfalarının ana penceredeki karşılıkları.
    /// Panelde içerik açan her widget'ın burada da bir sayfası var; ray
    /// üzerindeki eylem ikonları (sabitle, pencere değiştirici, ekle,
    /// ayarlar) ise sayfa değil, bu yüzden burada yer almıyorlar.
    case network
    case battery
    case disk
    case processor
    /// Uygulamanın kendi dosya alanı.
    case folders
}
