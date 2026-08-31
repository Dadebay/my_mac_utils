import SwiftUI
import GlassDoKit

/// Çapa (kenar ucu) ile baloncuğu tek bir kapalı yol olarak çizen `Shape`.
///
/// Bağlantı yokken (`connector == nil`) düz bir daire çizer — sürükleme
/// kenardan uzaklaşmadığında ekstra geometri hesaplamanın bir karşılığı yok.
/// Bağlantı varken tek bir `Path` içinde kısa boyun ve kusursuz daire iki
/// örtüşen alt yol olarak çizilir. Fill bunları tek silüet yapar; baloncuğun
/// bütün çevresini bağlantı yoluna katmadığımız için sürükleme sırasında
/// daire yıldız/cusp biçimine dönüşmez.
///
/// `bubbleCenter` ve `pinch` `animatableData` üzerinden SwiftUI'nin kendi
/// spring/interpolasyon sistemine bağlı: sürüklerken her karede doğrudan
/// atanıyor (anlık), bırakma sonrası `withAnimation(.spring(...))` ile
/// çağrıldığında ise boynun incelip kopması veya yeniden kalınlaşması akıcı
/// bir şekilde ara karelerden geçiyor.
struct MetaballBlobShape: Shape {
    var anchorCenter: CGPoint
    var anchorRadius: CGFloat
    var bubbleCenter: CGPoint
    var bubbleRadius: CGFloat
    /// `nil` → yalnızca düz daire (bağlantı yok).
    var pinch: Double?

    var animatableData: AnimatablePair<CGPoint.AnimatableData, AnimatablePair<CGFloat, Double>> {
        get {
            AnimatablePair(bubbleCenter.animatableData, AnimatablePair(bubbleRadius, pinch ?? 1))
        }
        set {
            bubbleCenter.animatableData = newValue.first
            bubbleRadius = newValue.second.first
            // `pinch`in kendisi `nil` durumunu taşıyamıyor (Animatable salt
            // sayısal); interpolasyon sırasında hep "bağlantı var" kabul
            // edilir — görsel olarak zararsız, çünkü `nil` yalnızca
            // baloncuk kenardan tamamen uzaklaştığında set ediliyor ve o an
            // zaten `pinch` da 1'e yakın oluyor.
            pinch = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard let pinch,
              let connector = MetaballConnector.make(
                  anchor: anchorCenter, anchorRadius: anchorRadius,
                  bubble: bubbleCenter, bubbleRadius: bubbleRadius,
                  pinch: pinch
              )
        else {
            return Circle().path(in: CGRect(
                x: bubbleCenter.x - bubbleRadius, y: bubbleCenter.y - bubbleRadius,
                width: bubbleRadius * 2, height: bubbleRadius * 2
            ))
        }

        var path = Path()
        path.move(to: connector.anchorNear)
        path.addCurve(
            to: connector.bubbleNear,
            control1: connector.controlNearAnchorSide,
            control2: connector.controlNearBubbleSide
        )
        path.addLine(to: connector.bubbleFar)
        path.addCurve(
            to: connector.anchorFar,
            control1: connector.controlFarBubbleSide,
            control2: connector.controlFarAnchorSide
        )
        path.closeSubpath()

        path.addEllipse(in: CGRect(
            x: connector.bubbleCenter.x - connector.bubbleRadius,
            y: connector.bubbleCenter.y - connector.bubbleRadius,
            width: connector.bubbleRadius * 2,
            height: connector.bubbleRadius * 2
        ))
        return path
    }
}
