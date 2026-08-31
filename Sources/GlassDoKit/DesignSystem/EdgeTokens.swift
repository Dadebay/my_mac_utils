import Foundation

public enum EdgeTokens {
    public static let railWidth: CGFloat = 44
    public static let railIconHitSize: CGFloat = 28
    public static let railRowHeight: CGFloat = 44
    public static let railIconCount = 8
    public static let railHeight: CGFloat = 16 + (CGFloat(railIconCount) * railRowHeight) + 16

    public static let panelWidth: CGFloat = 329
    public static let panelHeight: CGFloat = 417
    public static let sliverWidth: CGFloat = 6

    public static let sliverHideDelay: Duration = .seconds(2.5)

    /// Ray ↔ panel geçişi bir drawer hareketidir; taşma/bounce kullanmaz.
    public static let panelExpandDuration: Double = 0.26
    public static let panelCollapseDuration: Double = 0.22
}
