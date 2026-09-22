import Testing
import AppKit
@testable import GlassDoKit

struct EdgeGeometryTests {

    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("Sağ kenardaki ray ekranın sağına yapışık duruyor")
    func railFlushOnTrailingEdge() {
        let rail = EdgeGeometry.railFrame(edge: .trailing, top: 800, height: 236, visible: screen)
        #expect(rail.maxX == screen.maxX)
        #expect(rail.width == EdgeTokens.railWidth)
    }

    @Test("Sol kenardaki ray ekranın soluna yapışık duruyor")
    func railFlushOnLeadingEdge() {
        let rail = EdgeGeometry.railFrame(edge: .leading, top: 800, height: 236, visible: screen)
        #expect(rail.minX == screen.minX)
    }

    @Test("Ekran dışı dikey pozisyon görünür alana çekiliyor")
    func clampsOffScreenTop() {
        let clamped = EdgeGeometry.clampedTop(5000, height: 236, visible: screen)
        #expect(clamped <= screen.maxY - 236)
        #expect(clamped >= screen.minY)
    }

    @Test("Sağ kenarda panel sola doğru açılıyor ve ekran dışına taşmıyor")
    func expandsLeftOnTrailingEdge() {
        let rail = EdgeGeometry.railFrame(edge: .trailing, top: 800, height: 236, visible: screen)
        let expanded = EdgeGeometry.expandedFrame(
            railFrame: rail, edge: .trailing,
            panelSize: CGSize(width: 320, height: 420), visible: screen
        )
        #expect(expanded.maxX == screen.maxX)
        #expect(expanded.minX >= screen.minX)
        #expect(expanded.width == 320 + EdgeTokens.railWidth)
    }

    @Test("Sol kenarda panel sağa doğru açılıyor")
    func expandsRightOnLeadingEdge() {
        let rail = EdgeGeometry.railFrame(edge: .leading, top: 800, height: 236, visible: screen)
        let expanded = EdgeGeometry.expandedFrame(
            railFrame: rail, edge: .leading,
            panelSize: CGSize(width: 320, height: 420), visible: screen
        )
        #expect(expanded.minX == screen.minX)
        #expect(expanded.maxX <= screen.maxX)
    }

    @Test("Ekranın altına yakın ray genişleyince taşmıyor")
    func expandedFrameClampsAtBottom() {
        let rail = EdgeGeometry.railFrame(edge: .trailing, top: 10, height: 236, visible: screen)
        let expanded = EdgeGeometry.expandedFrame(
            railFrame: rail, edge: .trailing,
            panelSize: CGSize(width: 320, height: 420), visible: screen
        )
        #expect(expanded.minY >= screen.minY + 8)
    }

    @Test("Sağ kenarda sliver frame'i panelin sadece sliverWidth kadarını bırakıyor")
    func sliverSlidesTrailingEdgeOut() {
        let rail = EdgeGeometry.railFrame(edge: .trailing, top: 800, height: 236, visible: screen)
        let sliver = EdgeGeometry.sliverFrame(railFrame: rail, edge: .trailing, sliverWidth: 6)
        #expect(sliver.maxX == rail.maxX + (rail.width - 6))
        #expect(sliver.width == rail.width)
    }

    @Test("Sol kenarda sliver frame'i doğru yöne kayıyor")
    func sliverSlidesLeadingEdgeOut() {
        let rail = EdgeGeometry.railFrame(edge: .leading, top: 800, height: 236, visible: screen)
        let sliver = EdgeGeometry.sliverFrame(railFrame: rail, edge: .leading, sliverWidth: 6)
        #expect(sliver.minX == rail.minX - (rail.width - 6))
    }

    @Test("Ekranın sağ yarısındaki nokta trailing kenara yapışıyor")
    func detectsTrailingEdge() {
        let edge = EdgeGeometry.nearestEdge(point: NSPoint(x: 1500, y: 500), visible: screen)
        #expect(edge == .trailing)
    }

    @Test("Ekranın sol yarısındaki nokta leading kenara yapışıyor")
    func detectsLeadingEdge() {
        let edge = EdgeGeometry.nearestEdge(point: NSPoint(x: 400, y: 500), visible: screen)
        #expect(edge == .leading)
    }

    @Test("Ray özel genişlik verilince o genişlikte kenara yapışıyor")
    func railRespectsCustomWidth() {
        let rail = EdgeGeometry.railFrame(edge: .trailing, top: 800, height: 236, width: 64, visible: screen)
        #expect(rail.width == 64)
        #expect(rail.maxX == screen.maxX)
    }

    @Test("Ray yüksekliği ikon sayısıyla doğru hesaplanıyor")
    func railHeightMatchesIconCount() {
        let expected = 16 + (CGFloat(EdgeTokens.railIconCount) * EdgeTokens.railRowHeight) + 16
        #expect(EdgeTokens.railHeight == expected)
    }
}

struct PanelPresentationTests {

    @Test("Pinned modda hover çıkışı paneli kapatmıyor")
    func pinnedNeverCollapses() {
        #expect(PanelPresentation.shouldCollapseOnHoverExit(mode: .pinned) == false)
    }

    @Test("Rail ve sliver modunda hover çıkışı paneli kapatıyor")
    func nonPinnedCollapses() {
        #expect(PanelPresentation.shouldCollapseOnHoverExit(mode: .rail))
        #expect(PanelPresentation.shouldCollapseOnHoverExit(mode: .sliver))
    }

    @Test("Sliver modu kapalıyken rail'den sliver'a geçilmiyor")
    func railModeNeverAutoHides() {
        #expect(PanelPresentation.shouldAutoHideToSliver(mode: .rail, isExpanded: false) == false)
    }

    @Test("Sliver modunda ve kapalıyken otomatik gizleniyor")
    func sliverModeAutoHidesWhenCollapsed() {
        #expect(PanelPresentation.shouldAutoHideToSliver(mode: .sliver, isExpanded: false))
    }

    @Test("Sliver modunda ama açıkken gizlenmiyor")
    func sliverModeDoesNotHideWhileExpanded() {
        #expect(PanelPresentation.shouldAutoHideToSliver(mode: .sliver, isExpanded: true) == false)
    }
}
