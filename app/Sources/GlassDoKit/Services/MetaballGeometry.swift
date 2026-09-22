import Foundation
import CoreGraphics

/// Serbest baloncuğun ekran kenarıyla ilişkisi.
///
/// Tek bir zayıf durum ("isDocked": Bool) yerine açık bir durum makinesi:
/// her an baloncuğun ne yaptığı bu beş halden biriyle anlatılıyor, ikisi
/// aynı anda doğru olamaz.
public enum BubbleAttachment: Equatable, Sendable {
    /// Kenara tam yapışık — sıvı boyun görünmüyor, düz bir baskı var.
    case attached(edge: ScreenEdge)
    /// Kenardan ayrılıyor: `progress` 0 (henüz yapışık) ile 1 (kopma anı)
    /// arasında — boynun ne kadar incelmiş olduğu.
    case stretching(edge: ScreenEdge, progress: Double)
    /// Boyun kopuyor — kısa, tek seferlik geri çekilme animasyonu sürüyor.
    case detaching
    /// Tamamen serbest, kenarla hiçbir görsel bağı yok.
    case detached
    /// Serbest baloncuk kenara yaklaşıyor, boyun yeniden kuruluyor.
    case reattaching(edge: ScreenEdge)
}

/// Sıvı boynun mesafeye göre davranışını tanımlayan bölgeler.
///
/// Değerler `EdgePanelController.bubbleSize`'a görece değil, doğrudan
/// noktadır — referans tasarımda istenen mutlak aralıklar (spec'teki
/// "0–8 / 8–34 / 34–52 pt" bölgeleri) bire bir bunlar.
public enum MetaballZones {
    /// Bu mesafeye kadar tamamen yapışık sayılır — hem küçük fare
    /// titremelerini yutar hem de tıklama ile sürüklemeyi ayırt eden eşikle
    /// (bkz. `LiquidBubbleView`'daki `DragGesture(minimumDistance:)`) aynı
    /// büyüklük mertebesinde, tesadüf değil: ikisi de "bu henüz bir
    /// sürükleme değil" sorusuna cevap veriyor.
    public static let bondedDistance: CGFloat = 8
    /// Boynun görünür biçimde incelmeye başladığı mesafe.
    public static let thinningDistance: CGFloat = 34
    /// Normal (hızsız) bir sürüklemede kopma mesafesi.
    public static let detachDistance: CGFloat = 52
    /// Bunun üstündeki dışa yönlü hızda kopma mesafesi kısalır — belirgin
    /// bir fırlatma, tam 52 pt'ye ulaşmadan da "bırakma" sayılır.
    public static let flickVelocity: CGFloat = 900
    /// Hızlı fırlatmada etkili kopma mesafesi.
    public static let flickDetachDistance: CGFloat = 34
    /// Geri yaklaşırken bu mesafenin altına inmek "tam yapışacak" demek —
    /// sıfıra tam denk gelmesini beklemek gerçek fare hareketinde asla
    /// olmuyor.
    public static let snapDistance: CGFloat = 3

    /// Dışa yönlü hıza göre gerçek kopma mesafesi. Hızlı bir fırlatmada
    /// kullanıcı zaten "bırakıyorum" diyor — tam mesafeyi beklemek elini
    /// tutmuş gibi hissettirirdi.
    public static func effectiveDetachDistance(outwardVelocity: CGFloat) -> CGFloat {
        outwardVelocity >= flickVelocity ? flickDetachDistance : detachDistance
    }

    /// 0 = kenara tam yapışık, 1 = boynun koptuğu an. Sürüklerken her
    /// karede yeniden hesaplanıyor; kayıtlı bir animasyon değil.
    public static func progress(distance: CGFloat, outwardVelocity: CGFloat) -> Double {
        let threshold = effectiveDetachDistance(outwardVelocity: outwardVelocity)
        guard threshold > bondedDistance else { return 1 }
        let clamped = min(max(distance, bondedDistance), threshold)
        return Double((clamped - bondedDistance) / (threshold - bondedDistance))
    }

    /// Sürükleme kenardan uzaklaşırken hangi duruma girildiğini söyler.
    public static func classifyDetaching(
        distance: CGFloat, edge: ScreenEdge, outwardVelocity: CGFloat
    ) -> BubbleAttachment {
        if distance <= bondedDistance { return .attached(edge: edge) }
        if distance >= effectiveDetachDistance(outwardVelocity: outwardVelocity) { return .detaching }
        return .stretching(edge: edge, progress: progress(distance: distance, outwardVelocity: outwardVelocity))
    }

    /// Serbest baloncuk kenara yaklaşırken hangi duruma girildiğini söyler.
    public static func classifyReattaching(
        distance: CGFloat, edge: ScreenEdge, outwardVelocity: CGFloat
    ) -> BubbleAttachment {
        if distance <= snapDistance { return .attached(edge: edge) }
        if distance >= effectiveDetachDistance(outwardVelocity: max(outwardVelocity, 0)) { return .detached }
        return .reattaching(edge: edge)
    }

    /// Apple'ın momentum projeksiyonu (bkz. *Designing Fluid Interfaces*,
    /// WWDC 2018): bırakma anındaki konum değil, hızın taşıyacağı konum
    /// karar veriyor — yavaşça 10 pt'de bırakılan bir sürükleme geri
    /// yapışır, hızla 10 pt'de fırlatılan bir sürükleme kopar.
    public static func projectedDistance(
        current: CGFloat, outwardVelocity: CGFloat, decelerationRate: CGFloat = 0.998
    ) -> CGFloat {
        current + (outwardVelocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// Bırakma anında: kopmuş mu sayılsın, yoksa kenara mı geri çekilsin?
    /// Projeksiyon kopma mesafesini geçiyorsa evet.
    public static func shouldDetachOnRelease(distance: CGFloat, outwardVelocity: CGFloat) -> Bool {
        let projected = projectedDistance(current: distance, outwardVelocity: outwardVelocity)
        return projected >= effectiveDetachDistance(outwardVelocity: outwardVelocity)
    }

    /// Serbest bir baloncuk bırakıldığında: kenara mı yapışsın?
    /// `outwardVelocity` negatifse (kenara doğru hareket) projeksiyon
    /// mesafeyi düşürür.
    public static func shouldReattachOnRelease(distance: CGFloat, outwardVelocity: CGFloat) -> Bool {
        let projected = projectedDistance(current: distance, outwardVelocity: outwardVelocity)
        return projected <= snapDistance
    }
}

/// İki daire (sabit kenar-ucu ve sürüklenen baloncuk) arasındaki sıvı
/// bağlantının çizim geometrisi.
///
/// Tamamen "yerel" bir eksende çalışır: `anchor` ve `bubble` hangi
/// koordinat sisteminde verilirse geometri onda üretilir — sol/sağ kenar
/// aynalaması burada değil, çağıranın `anchor`/`bubble` noktalarını nasıl
/// yerleştirdiğinde. Bu yüzden fonksiyonun kendisi kenardan bağımsız ve
/// test edilebilir; `EdgePanelController` sol kenarda `anchor.x <
/// bubble.x`, sağ kenarda tam tersini vererek aynı fonksiyonu kullanır.
public struct MetaballConnector: Equatable, Sendable {
    public let anchorCenter: CGPoint
    public let anchorRadius: CGFloat
    public let bubbleCenter: CGPoint
    public let bubbleRadius: CGFloat

    /// Kenar tarafındaki iki teğet nokta (dairenin gerçek sınırında).
    public let anchorNear: CGPoint
    public let anchorFar: CGPoint
    /// Baloncuk tarafındaki iki teğet nokta.
    public let bubbleNear: CGPoint
    public let bubbleFar: CGPoint
    /// Bel eğrisinin kontrol noktaları — ikisi de aynı dik ofsete
    /// (`waistWidth`) çekilir, bu da ortada tek, simetrik bir incelme
    /// oluşturur.
    public let controlNearAnchorSide: CGPoint
    public let controlNearBubbleSide: CGPoint
    public let controlFarAnchorSide: CGPoint
    public let controlFarBubbleSide: CGPoint

    /// Merkezler arası eksene dik birim vektör — çağıran taraf, gerçek
    /// dairenin uzak yarısını (bağlantının olmadığı taraf) çizmek için
    /// açı hesaplarken kullanır.
    public let perpendicular: CGPoint
    public let axisAngle: CGFloat

    /// - Parameter pinch: 0 = bel tam dolgun (dairelerin neredeyse
    ///   birleştiği hâli), 1 = bel kıl payı kalmış (kopmanın eşiği).
    public static func make(
        anchor: CGPoint, anchorRadius: CGFloat,
        bubble: CGPoint, bubbleRadius: CGFloat,
        pinch: Double
    ) -> MetaballConnector? {
        let dx = bubble.x - anchor.x
        let dy = bubble.y - anchor.y
        let distance = (dx * dx + dy * dy).squareRoot()
        // Merkezler üst üsteyse (henüz sürüklenmedi) yön tanımsız — bu
        // durumda çağıran zaten yalın bir daire çiziyor, bağlantıya gerek
        // yok.
        guard distance > 0.5 else { return nil }

        let ux = dx / distance, uy = dy / distance
        let px = -uy, py = ux

        let clampedPinch = min(max(pinch, 0), 1)
        // Bağlantı baloncuğun kendisinden daha baskın görünmemeli. Eski
        // geometri baloncuğa tam yarıçapından bağlanıyor, bütün daireyi
        // çekiştirip dört sivri uç üretiyordu. Kenarda kısa bir menisküs,
        // baloncukta ise yarıçapın yaklaşık yarısı kadar bir ağız yeterli.
        let anchorHalfWidth = max(
            2.5,
            anchorRadius * (0.62 - 0.44 * CGFloat(clampedPinch))
        )
        let bubbleHalfWidth = max(
            3.5,
            bubbleRadius * (0.48 - 0.34 * CGFloat(clampedPinch))
        )

        func offset(_ point: CGPoint, _ vx: CGFloat, _ vy: CGFloat, _ amount: CGFloat) -> CGPoint {
            CGPoint(x: point.x + vx * amount, y: point.y + vy * amount)
        }

        let anchorNear = offset(anchor, px, py, anchorHalfWidth)
        let anchorFar = offset(anchor, px, py, -anchorHalfWidth)

        // Baloncuk bağlantı noktaları dairenin kenara bakan yayında kalır.
        // x/y eksenindeki en üst ve en alt noktalara bağlanmak cusp üretir;
        // Pisagor ile gerçek çember üzerindeki iki sakin teğet noktayı bul.
        let alongCircle = max(
            0,
            bubbleRadius * bubbleRadius - bubbleHalfWidth * bubbleHalfWidth
        ).squareRoot()
        let bubbleFacingAnchor = offset(bubble, ux, uy, -alongCircle)
        let bubbleNear = offset(bubbleFacingAnchor, px, py, bubbleHalfWidth)
        let bubbleFar = offset(bubbleFacingAnchor, px, py, -bubbleHalfWidth)

        // Kontrol noktaları eksen boyunca merkeze doğru çekilir (eğrinin
        // "gövdesi") ve dik yönde bel genişliğine basılır (eğrinin
        // "inceliği"). İki nokta da aynı bel genişliğini paylaşması, ortada
        // tek ve simetrik bir boğum oluşturuyor — iki ayrı eğri birbirine
        // dikişle değil, aynı denklemle bağlanmış gibi görünüyor.
        let visibleSpan = max(distance - alongCircle, 0)
        let axialPull = min(max(visibleSpan * 0.46, 3), 24)
        let controlNearAnchorSide = offset(anchorNear, ux, uy, axialPull)
        let controlNearBubbleSide = offset(bubbleNear, ux, uy, -axialPull)
        let controlFarAnchorSide = offset(anchorFar, ux, uy, axialPull)
        let controlFarBubbleSide = offset(bubbleFar, ux, uy, -axialPull)

        return MetaballConnector(
            anchorCenter: anchor, anchorRadius: anchorRadius,
            bubbleCenter: bubble, bubbleRadius: bubbleRadius,
            anchorNear: anchorNear, anchorFar: anchorFar,
            bubbleNear: bubbleNear, bubbleFar: bubbleFar,
            controlNearAnchorSide: controlNearAnchorSide,
            controlNearBubbleSide: controlNearBubbleSide,
            controlFarAnchorSide: controlFarAnchorSide,
            controlFarBubbleSide: controlFarBubbleSide,
            perpendicular: CGPoint(x: px, y: py),
            axisAngle: atan2(uy, ux)
        )
    }
}
