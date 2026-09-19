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

    public static func expandedFrame(railFrame: NSRect, edge: ScreenEdge, panelSize: CGSize, visible: NSRect) -> NSRect {
        let totalWidth = panelSize.width + railFrame.width
        let height = min(panelSize.height, visible.height - 16)
        let x = edge == .trailing ? railFrame.maxX - totalWidth : railFrame.minX

        var y = railFrame.maxY - height
        y = min(max(y, visible.minY + 8), visible.maxY - height - 8)

        var f = NSRect(x: x, y: y, width: totalWidth, height: height)
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
