import AppKit

/// Masaüstünde serbestçe duran ölçer penceresi.
///
/// `PoppedNotePanel` ile aynı desen ve aynı gerekçeler: kenarlıksız (kendi
/// yuvarlatılmış camını çiziyor), tüm Space'lerde görünür, uygulama arka
/// plana geçince kapanmaz. Fark, bunun hiç klavye istememesi — içinde
/// yazılacak bir şey yok, yalnızca okunuyor. Bu yüzden asla anahtar pencere
/// olmuyor: widget'a tıklamak GlassDo'yu öne getirmiyor, kullanıcı
/// çalıştığı uygulamadan kopmuyor.
final class DesktopWidgetPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Kartın her yerinden tutulup taşınabiliyor: widget'ın tamamı
        // tutamak, ayrı bir başlık şeridi yok.
        isMovableByWindowBackground = true

        // Gerçek masaüstü widget'ları gibi sıradan pencere sırasına uyuyor:
        // `.floating` olsaydı hangi uygulama etkin olursa olsun her şeyin
        // üstünde kalır, kullanıcının önündeki pencereyi örterdi.
        level = .normal
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]

        minSize = NSSize(width: 260, height: 180)
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
