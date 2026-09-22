import AppKit

public enum ScreenEdge: String, Sendable, CaseIterable {
    case leading, trailing
}

public enum EdgeGeometry {

    public static func clampedTop(_ top: CGFloat, height: CGFloat, visible: NSRect) -> CGFloat {
        min(max(top, visible.minY), visible.maxY - height)
    }

    public static func railFrame(
        edge: ScreenEdge, top: CGFloat, height: CGFloat,
        width: CGFloat = EdgeTokens.railWidth, visible: NSRect
    ) -> NSRect {
        let x = edge == .trailing ? visible.maxX - width : visible.minX
        let clampedY = clampedTop(top, height: height, visible: visible)
        return NSRect(x: x, y: clampedY, width: width, height: height)
    }

    /// Açık panelin penceresi.
    ///
    /// Pencerenin **üst kenarı rayın üst kenarına çivili**: panel yalnızca
    /// aşağı doğru açılıyor. Önceden yükseklik sabit alınıp pencere ekrana
    /// sığsın diye yukarı kaydırılıyordu; ray da pencerenin tepesinde durduğu
    /// için ikonlar açılış sırasında yukarı zıplıyordu. Şimdi kaydırılan şey
    /// pencere değil, panelin boyu: aşağıda ne kadar yer varsa panel o kadar
    /// uzuyor, ray ekranda hiç kımıldamıyor.
    public static func expandedFrame(railFrame: NSRect, edge: ScreenEdge, panelSize: CGSize, visible: NSRect) -> NSRect {
        let totalWidth = panelSize.width + railFrame.width
        let x = edge == .trailing ? railFrame.maxX - totalWidth : railFrame.minX

        let top = railFrame.maxY
        // Alt kenarda 8 pt pay: pencere ekranın dibine yapışmasın.
        let available = max(top - (visible.minY + 8), 0)
        let height = min(min(panelSize.height, visible.height - 16), available)

        var f = NSRect(x: x, y: top - height, width: totalWidth, height: height)
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - totalWidth)
        return f
    }

    public static func sliverFrame(railFrame: NSRect, edge: ScreenEdge, sliverWidth: CGFloat) -> NSRect {
        var f = railFrame
        switch edge {
        case .leading: f.origin.x = railFrame.minX - (railFrame.width - sliverWidth)
        case .trailing: f.origin.x = railFrame.minX + (railFrame.width - sliverWidth)
        }
        return f
    }

    public static func nearestEdge(point: NSPoint, visible: NSRect) -> ScreenEdge {
        point.x > visible.midX ? .trailing : .leading
    }
}
