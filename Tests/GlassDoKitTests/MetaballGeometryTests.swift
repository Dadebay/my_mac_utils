import Testing
import CoreGraphics
@testable import GlassDoKit

struct MetaballZonesTests {

    // MARK: - Progress clamp

    @Test("Yapışık mesafede ilerleme sıfır")
    func progressZeroWhenBonded() {
        #expect(MetaballZones.progress(distance: 0, outwardVelocity: 0) == 0)
        #expect(MetaballZones.progress(distance: MetaballZones.bondedDistance, outwardVelocity: 0) == 0)
    }

    @Test("Kopma mesafesinde ilerleme bir")
    func progressOneAtDetach() {
        let progress = MetaballZones.progress(
            distance: MetaballZones.detachDistance, outwardVelocity: 0
        )
        #expect(progress == 1)
    }

    @Test("İlerleme aralığın dışına taşmıyor")
    func progressClampsBeyondRange() {
        let beyond = MetaballZones.progress(distance: 500, outwardVelocity: 0)
        #expect(beyond == 1)
        let before = MetaballZones.progress(distance: -50, outwardVelocity: 0)
        #expect(before == 0)
    }

    @Test("İlerleme mesafeyle birlikte monoton artıyor")
    func progressIsMonotonic() {
        let near = MetaballZones.progress(distance: 15, outwardVelocity: 0)
        let mid = MetaballZones.progress(distance: 30, outwardVelocity: 0)
        let far = MetaballZones.progress(distance: 45, outwardVelocity: 0)
        #expect(near < mid)
        #expect(mid < far)
    }

    // MARK: - Kopma eşiği ve hız etkisi

    @Test("Normal hızda tam kopma mesafesi kullanılıyor")
    func effectiveDistanceAtRest() {
        #expect(MetaballZones.effectiveDetachDistance(outwardVelocity: 0) == MetaballZones.detachDistance)
    }

    @Test("Hızlı fırlatmada kopma mesafesi kısalıyor")
    func fastFlickShortensDetachDistance() {
        let fast = MetaballZones.effectiveDetachDistance(outwardVelocity: MetaballZones.flickVelocity + 100)
        #expect(fast == MetaballZones.flickDetachDistance)
        #expect(fast < MetaballZones.detachDistance)
    }

    @Test("Sınırdaki hız hâlâ tam mesafeden ayrılmış davranıyor")
    func velocityThresholdIsInclusive() {
        let atThreshold = MetaballZones.effectiveDetachDistance(outwardVelocity: MetaballZones.flickVelocity)
        #expect(atThreshold == MetaballZones.flickDetachDistance)
    }

    @Test("classifyDetaching kopma mesafesinde .detaching döndürüyor")
    func classifyDetachingCrossesThreshold() {
        let justBefore = MetaballZones.classifyDetaching(
            distance: MetaballZones.detachDistance - 1, edge: .trailing, outwardVelocity: 0
        )
        let atThreshold = MetaballZones.classifyDetaching(
            distance: MetaballZones.detachDistance, edge: .trailing, outwardVelocity: 0
        )
        guard case .stretching = justBefore else {
            Issue.record("Eşikten hemen önce hâlâ geriliyor olmalıydı")
            return
        }
        #expect(atThreshold == .detaching)
    }

    @Test("classifyDetaching yapışma bölgesinde .attached döndürüyor")
    func classifyDetachingStaysAttachedWithinBond() {
        let result = MetaballZones.classifyDetaching(distance: 3, edge: .leading, outwardVelocity: 0)
        #expect(result == .attached(edge: .leading))
    }

    // MARK: - Momentum projeksiyonu ve yeniden birleşme kararı

    @Test("Hız sıfırken projeksiyon mevcut mesafeyle aynı")
    func projectionIsIdentityAtZeroVelocity() {
        let projected = MetaballZones.projectedDistance(current: 20, outwardVelocity: 0)
        #expect(projected == 20)
    }

    @Test("Dışa yönlü hız projeksiyonu ileri taşıyor")
    func projectionMovesForwardWithOutwardVelocity() {
        let projected = MetaballZones.projectedDistance(current: 10, outwardVelocity: 500)
        #expect(projected > 10)
    }

    @Test("Yavaş bırakma eşiğin altında kalınca kenara geri çekiliyor")
    func slowReleaseSnapsBack() {
        #expect(MetaballZones.shouldDetachOnRelease(distance: 15, outwardVelocity: 5) == false)
    }

    @Test("Eşiğe yakın hızlı fırlatma kopmaya yetiyor")
    func fastFlickNearThresholdDetaches() {
        // 40 pt + yüksek dışa hız: normal eşiğin (52) altında ama fırlatma
        // eşiğinin (34) üstünde — projeksiyon onu daha da ileri taşıyacak.
        #expect(MetaballZones.shouldDetachOnRelease(distance: 40, outwardVelocity: 1200))
    }

    @Test("Kenara doğru hızla bırakılan serbest baloncuk yeniden yapışıyor")
    func inwardVelocitySnapsFreeBubbleBack() {
        // Kenara doğru (negatif) hız: mesafe azalıyor gibi hesaplanır.
        #expect(MetaballZones.shouldReattachOnRelease(distance: 6, outwardVelocity: -400))
    }

    @Test("Dışarı doğru hızla bırakılan serbest baloncuk yapışmıyor")
    func outwardVelocityKeepsFreeBubbleDetached() {
        #expect(MetaballZones.shouldReattachOnRelease(distance: 6, outwardVelocity: 400) == false)
    }

    @Test("classifyReattaching bağlanma mesafesinde .attached döndürüyor")
    func classifyReattachingSnapsWhenClose() {
        let result = MetaballZones.classifyReattaching(distance: 1, edge: .trailing, outwardVelocity: 0)
        #expect(result == .attached(edge: .trailing))
    }

    @Test("classifyReattaching uzak mesafede .detached döndürüyor")
    func classifyReattachingStaysDetachedWhenFar() {
        let result = MetaballZones.classifyReattaching(distance: 200, edge: .trailing, outwardVelocity: 0)
        #expect(result == .detached)
    }
}

struct MetaballConnectorTests {

    @Test("Merkezler üst üsteyken bağlantı üretilmiyor")
    func returnsNilWhenCentersCoincide() {
        let connector = MetaballConnector.make(
            anchor: CGPoint(x: 0, y: 0), anchorRadius: 10,
            bubble: CGPoint(x: 0, y: 0), bubbleRadius: 28,
            pinch: 0
        )
        #expect(connector == nil)
    }

    @Test("Pinch arttıkça bel genişliği daralıyor")
    func waistNarrowsAsPinchIncreases() {
        let loose = MetaballConnector.make(
            anchor: CGPoint(x: 0, y: 0), anchorRadius: 20,
            bubble: CGPoint(x: 60, y: 0), bubbleRadius: 28,
            pinch: 0
        )!
        let tight = MetaballConnector.make(
            anchor: CGPoint(x: 0, y: 0), anchorRadius: 20,
            bubble: CGPoint(x: 60, y: 0), bubbleRadius: 28,
            pinch: 1
        )!

        // Bel genişliği kontrol noktalarının eksene dik uzaklığı — burada
        // eksen yatay (y=0), o yüzden doğrudan |y| karşılaştırılabilir.
        let looseWaist = abs(loose.controlNearAnchorSide.y)
        let tightWaist = abs(tight.controlNearAnchorSide.y)
        #expect(tightWaist < looseWaist)
    }

    @Test("Sol ve sağ kenar geometrisi x ekseninde aynalanıyor")
    func mirrorsAcrossLeadingAndTrailingEdges() {
        // Sağ kenar: çapa solda (küçük x), baloncuk sağda — dışarı = +x.
        let trailing = MetaballConnector.make(
            anchor: CGPoint(x: 100, y: 400), anchorRadius: 20,
            bubble: CGPoint(x: 140, y: 400), bubbleRadius: 28,
            pinch: 0.4
        )!
        // Sol kenar: aynı yapılandırmanın x ekseninde ayna görüntüsü —
        // çapa sağda, baloncuk solda.
        let leading = MetaballConnector.make(
            anchor: CGPoint(x: -100, y: 400), anchorRadius: 20,
            bubble: CGPoint(x: -140, y: 400), bubbleRadius: 28,
            pinch: 0.4
        )!

        // Sabit +90° döndürme kuralı, ayna yansımasında hangi teğet
        // noktanın "near" hangisinin "far" diye adlandırıldığını
        // değiştirir (yansıma bir döndürme değil) — ama iz düşen kapalı
        // yol simetrik (üst/alt bel genişliği eşit) olduğu için bu yalnız
        // bir etiketleme farkı, çizilen piksel aynı. Gerçek görsel
        // değişmez şu ikisi: merkezden dik uzaklığın büyüklüğü (|Δy|) ve
        // x'in işareti.
        #expect(abs(trailing.anchorNear.y - trailing.anchorCenter.y) == abs(leading.anchorNear.y - leading.anchorCenter.y))
        #expect(trailing.anchorCenter.x == -leading.anchorCenter.x)
        #expect(trailing.bubbleCenter.x == -leading.bubbleCenter.x)

        // Bel genişliği (eksene dik uzaklığın büyüklüğü) iki kenarda birebir
        // aynı — sürüklemenin "ne kadar incelmiş" hissi sol/sağda farklı
        // olmuyor.
        let trailingWaist = abs(trailing.controlNearAnchorSide.y - trailing.anchorCenter.y)
        let leadingWaist = abs(leading.controlNearAnchorSide.y - leading.anchorCenter.y)
        #expect(trailingWaist == leadingWaist)
    }

    @Test("Baloncuk bağlantısı çemberde, kenar ağzı çapa içinde kalıyor")
    func connectorMouthStaysInsideItsSurfaces() {
        let connector = MetaballConnector.make(
            anchor: CGPoint(x: 0, y: 0), anchorRadius: 20,
            bubble: CGPoint(x: 90, y: 30), bubbleRadius: 28,
            pinch: 0.7
        )!

        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        }

        #expect(distance(connector.anchorNear, connector.anchorCenter) < 20)
        #expect(distance(connector.anchorFar, connector.anchorCenter) < 20)
        #expect(abs(distance(connector.bubbleNear, connector.bubbleCenter) - 28) < 0.001)
        #expect(abs(distance(connector.bubbleFar, connector.bubbleCenter) - 28) < 0.001)
    }

    @Test("Bağlantı ağzı baloncuğun kenara bakan yarısında kalıyor")
    func bubbleMouthFacesAnchor() {
        let connector = MetaballConnector.make(
            anchor: CGPoint(x: 0, y: 0), anchorRadius: 14,
            bubble: CGPoint(x: 70, y: 0), bubbleRadius: 28,
            pinch: 0.5
        )!

        #expect(connector.bubbleNear.x < connector.bubbleCenter.x)
        #expect(connector.bubbleFar.x < connector.bubbleCenter.x)
        #expect(connector.bubbleNear.y > connector.bubbleCenter.y)
        #expect(connector.bubbleFar.y < connector.bubbleCenter.y)
    }
}
