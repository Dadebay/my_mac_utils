import SwiftUI

/// En sık tıklanan kontroller (checkbox, ray ikonları) hiçbir basma geri
/// bildirimi vermiyordu — tıklamanın algılandığını doğrulayan görsel bir
/// işaret yoktu. `find-animation-opportunities` denetiminden: Amaç =
/// Feedback, Sıklık = günde onlarca kez → yalnızca hafif, hızlı hareket
/// (120ms, %94 ölçek) uygun; daha büyük veya yavaş bir efekt bu sıklıkta
/// yorucu olurdu.
public struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat

    public init(scale: CGFloat = 0.94) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PressScaleButtonStyle {
    static var pressScale: PressScaleButtonStyle { PressScaleButtonStyle() }
    static func pressScale(_ scale: CGFloat) -> PressScaleButtonStyle { PressScaleButtonStyle(scale: scale) }
}
