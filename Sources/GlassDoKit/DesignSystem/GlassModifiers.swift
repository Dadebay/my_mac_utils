import SwiftUI

private struct AdaptiveGlassCapsule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    Capsule().fill(.background)
                }
            }
            .glassEffect(reduceTransparency ? .clear : .regular, in: .capsule)
    }
}

private struct AdaptiveGlassCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(.background)
                }
            }
            .glassEffect(reduceTransparency ? .clear : .regular, in: .rect(cornerRadius: cornerRadius))
    }
}

private struct AdaptiveGlassShell: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let edge: ScreenEdge
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(shape.fill(.black.opacity(reduceTransparency ? 0.95 : 0.8)))
            .glassEffect(.clear, in: shape)
            .clipShape(shape)
    }

    private var shape: UnevenRoundedRectangle {
        switch edge {
        case .trailing:
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius, bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: 0, topTrailingRadius: 0
            )
        case .leading:
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0,
                bottomTrailingRadius: cornerRadius, topTrailingRadius: cornerRadius
            )
        }
    }
}

public extension View {
    func adaptiveGlassCapsule() -> some View {
        modifier(AdaptiveGlassCapsule())
    }

    func adaptiveGlassCard(cornerRadius: CGFloat = Layout.cardCornerRadius) -> some View {
        modifier(AdaptiveGlassCard(cornerRadius: cornerRadius))
    }

    func adaptiveGlassShell(edge: ScreenEdge, cornerRadius: CGFloat = Layout.panelCornerRadius) -> some View {
        modifier(AdaptiveGlassShell(edge: edge, cornerRadius: cornerRadius))
    }
}
