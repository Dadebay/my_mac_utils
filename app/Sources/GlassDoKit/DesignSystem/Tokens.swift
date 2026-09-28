import SwiftUI

public enum Layout {
    /// Köşe yarıçapı ölçeği.
    ///
    /// Arayüzde on dokuz ayrı yarıçap dolaşıyordu (5, 6, 7, 8, 9, 10, 11,
    /// 12, 13, 14, 15, 16, 18, 20, 22, 24…). Aradaki bir puntoluk farklar
    /// gözle ayırt edilmiyor ama her yeni yüzeyde "kaç yazayım?" sorusunu
    /// doğuruyor ve komşu iki kartın farklı yuvarlanmasıyla sonuçlanıyordu.
    ///
    /// Basamaklar uydurulmadı: var olan değerlerin kümelendiği yerlerden
    /// çıkarıldı, her basamak kendi kümesinin en çok kullanılan üyesine
    /// yakın duruyor.
    ///
    /// Ölçeğin dışında bilerek bırakılan tek grup var: ölçer
    /// çubuklarının, sparkline uçlarının ve iki-üç punto yüksekliğindeki
    /// dolguların yarıçapı (1, 1.5, 2, 2.5, 3). Bunlar kendi
    /// yüksekliklerinin yarısı kadar yuvarlanıyor — bir ölçek basamağına
    /// oturtmak üç punto yüksekliğindeki çubuğu hapa çevirir. Yerlerinde
    /// sayı olarak duruyorlar.
    public enum Radius {
        /// Küçük rozetler, satır içi jetonlar, küçük küçük resimler.
        public static let small: CGFloat = 6
        /// Düğmeler, giriş alanları, liste satırı vurguları.
        public static let medium: CGFloat = 9
        /// Panel içi bloklar, açılır listeler.
        public static let large: CGFloat = 12
        /// Sayfa ve panel kartları — bir yüzeyin üstünde duran kutular.
        public static let card: CGFloat = 16
        /// Pencere ölçeğindeki cam yüzeyler: kenar paneli, pencere
        /// değiştirici bindirmesi.
        public static let panel: CGFloat = 22
        /// Bildirim Merkezi widget'ının köşesi. Ölçeğin bir basamağı
        /// değil, macOS'un kendi değeri: ayarlardaki widget önizlemesi
        /// gerçek widget'ı taklit ettiği için sistemle birebir kalmalı,
        /// ölçek değişse bile buna dokunulmuyor.
        public static let systemWidget: CGFloat = 24
    }

    public static let tightGutter: CGFloat = 8
    /// Pencere araç çubuğunun içeriğini kenardan ayıran pay. Sayfa
    /// içerikleri de bunu kullanıyor: araç çubuğundaki sayfa rozeti ile
    /// altındaki ilk sütun tek bir dikey çizgide başlasın diye.
    public static let toolbarSideInset: CGFloat = 14
}

public enum Motion {
    public static let expand = Animation.spring(response: 0.34, dampingFraction: 0.82)
    public static let collapse = Animation.spring(response: 0.28, dampingFraction: 0.9)
    public static let toggle = Animation.snappy(duration: 0.2)
    public static let iconVisibility = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    public static let railSelection = Animation.spring(response: 0.32, dampingFraction: 1.0)
    public static let panelContentAppearance = Animation
        .timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
        .delay(0.03)
    public static let panelContentDisappearance = Animation
        .timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
    /// Panel zaten açıkken bir ikondan diğerine geçerken kullanılır —
    /// `panelContentAppearance`'ın aksine gecikmesi yok: panel çerçevesi
    /// zaten yerinde, içerik anında tepki vermeli.
    public static let panelContentSwapIn = Animation
        .timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    public static let panelContentSwapOut = Animation
        .timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
    /// Liste satırları alttan yukarı, sırayla belirirken kullanılır.
    /// Panel açıldığında içerik tek blok hâlinde "yapışıp" kalmasın,
    /// akarak yerleşsin diye — sönümleme tam değil, satırın sonunda
    /// minik bir yerleşme var.
    public static let listReveal = Animation.spring(response: 0.42, dampingFraction: 0.86)

    /// İki komşu satırın belirmesi arasındaki gecikme. Küçük tutuluyor:
    /// on satırlık bir listede toplam gecikme çeyrek saniyeyi geçince
    /// akış değil bekleme hissi veriyor.
    public static let listRevealStagger: Double = 0.035

    /// Bir ölçüm değeri (CPU, bellek, ağ…) yenilendiğinde kullanılır — her
    /// sistem ölçer yüzeyinde (ana pencere, panel, menü çubuğu popover'ı)
    /// aynı his için tek yerden ayarlanabilsin diye.
    public static let dataUpdate = Animation.spring(response: 0.4, dampingFraction: 1.0)
}

public enum Palette {
    public static let projectColors = [
        "#5E9BFF", "#FF9F43", "#8B5CF6",
        "#34C759", "#FF453A", "#64D2FF",
    ]
}
