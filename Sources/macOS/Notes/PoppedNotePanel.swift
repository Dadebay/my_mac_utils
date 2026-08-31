import AppKit

/// Sticky Notes'taki gibi ekranda serbestçe duran görev listesi penceresi.
/// Uygulama arka plana geçse de kapanmaz ve tüm masaüstlerinde (Space)
/// görünür — ama gerçek Stickies'te olduğu gibi NORMAL pencere sırasına
/// uyar: başka bir uygulamaya tıklanınca onun pencereleri notun önüne geçer.
final class PoppedNotePanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // Kenarlıksız: sistemin trafik ışıkları yuvarlatılmış içeriğin
            // DIŞINDA, köşede asılı kalıyordu. Kapatma/renk düğmeleri artık
            // notun kendi başlık şeridinin içinde çiziliyor.
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Başlık şeridinin boş alanından sürüklenebilsin.
        isMovableByWindowBackground = true

        // `.floating` seviyesi ekranda HER ZAMAN normal pencerelerin
        // üstünde çizilir — hangi uygulama etkin olursa olsun. Bu yüzden
        // Chrome'a tıklayınca Chrome öne "geliyordu" ama not görsel olarak
        // hâlâ üstünde kalıyor, kullanıcıya hiçbir şey olmamış gibi
        // görünüyordu. Gerçek Stickies gibi `.normal` seviyede, sıradan bir
        // pencere olarak diğer uygulamaların gerisine düşebilmeli.
        level = .normal
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        // Panel yalnızca metin alanı gibi gerçekten klavye isteyen bir
        // denetime tıklanınca anahtar pencere olur. Bu olmadan nota yapılan
        // her tıklama uygulamayı etkin tutuyordu; arkadaki bir Chrome
        // penceresine tıklandığında o pencere öne gelmiyordu.
        becomesKeyOnlyIfNeeded = true

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]

        minSize = NSSize(width: 260, height: 240)
        animationBehavior = .utilityWindow
    }

    // Metin yazılabilmesi için anahtar pencere olabilmeli.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
