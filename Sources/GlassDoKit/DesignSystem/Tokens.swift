import SwiftUI

public enum Layout {
    public static let panelCornerRadius: CGFloat = 22
    public static let cardCornerRadius: CGFloat = 16
    public static let rowHeight: CGFloat = 34
    public static let gutter: CGFloat = 14
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
