import SwiftUI
import SwiftData
import GlassDoKit

/// Serbest GlassDo baloncuğu — kenara sıvı bir boyunla bağlı, kenardan
/// yeterince uzaklaşınca kopan, geri yaklaşınca yeniden birleşen hâli.
///
/// Panelin çerçevesi artık sabit `bubbleSize` değil: `EdgePanelController`
/// kenara yakınken bunu kenar-ucundan baloncuğa kadar uzanan geniş, şeffaf
/// bir tuvale büyütüyor (bkz. `liquidCanvasFrame`). Bu görünüm o tuvalin
/// tamamını dolduruyor ama yalnızca gerçek baloncuk dairesi tıklanabilir —
/// geri kalan her yer `allowsHitTesting(false)`, masaüstü tıklamalarını
/// engellemeden geçiriyor (rail'in kendi şeffaf kenar boşluklarıyla aynı
/// teknik, bkz. `EdgeShellView.railPlaceholder`).
struct LiquidBubbleView: View {
    @Environment(EdgePanelController.self) private var controller
    @Query(filter: Task.activePredicate()) private var activeTasks: [Task]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isDragging = false
    /// Kopma anının kısa "1.00 → 1.025 → 1.00" nabzı — sürekli bir sallanma
    /// değil, tek seferlik ve çok hafif.
    @State private var detachPulse = false

    private var bubbleRadius: CGFloat { EdgePanelController.bubbleSize / 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Tuvalin geri kalanı: baloncuğun dışındaki her nokta tamamen
            // şeffaf ve tıklamayı geçiriyor.
            Color.clear.allowsHitTesting(false)

            blobMaterial
                .allowsHitTesting(false)

            bubbleContent
                .scaleEffect(detachPulse ? 1.025 : 1)
                .position(controller.liquidBubbleCenter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Panel her zaman koyu — bkz. `EdgeShellView`'daki aynı not.
        .preferredColorScheme(.dark)
        .onChange(of: controller.attachment) { _, newValue in
            guard case .detaching = newValue, !reduceMotion else { return }
            // Boynun koptuğu an: kısa, tek seferlik bir nabız. Sürekli bir
            // sallanmaya dönüşmesin diye ikinci `withAnimation` geri
            // getiriyor, yeniden tetiklenmiyor.
            withAnimation(.easeOut(duration: 0.09)) { detachPulse = true }
            withAnimation(.easeOut(duration: 0.1).delay(0.08)) { detachPulse = false }
        }
    }

    /// Çapa + boyun + baloncuğun tek parça sıvı yüzeyi. Bağlantı yokken
    /// `MetaballBlobShape` zaten düz bir daireye düşüyor, o yüzden burada
    /// "bağlı mı değil mi" diye ayrıca dallanmaya gerek yok.
    private var blobMaterial: some View {
        let shape = MetaballBlobShape(
            anchorCenter: controller.liquidAnchorCenter,
            anchorRadius: EdgePanelController.anchorRadius,
            bubbleCenter: controller.liquidBubbleCenter,
            bubbleRadius: bubbleRadius,
            pinch: controller.liquidPinch
        )

        return Color.clear
            .background {
                if reduceTransparency {
                    // Malzeme değil, düz bir dolgu — daha yüksek kontrast,
                    // arkadaki içerik hiç sızmıyor.
                    shape.fill(Color.black.opacity(0.94))
                } else {
                    Color.clear.glassEffect(
                        .regular.tint(Color.black.opacity(0.42)),
                        in: shape
                    )
                }
            }
            .animation(
                reduceMotion || isDragging ? nil : .spring(response: 0.34, dampingFraction: 0.97),
                value: controller.liquidBubbleCenter
            )
            .animation(
                reduceMotion || isDragging ? nil : .spring(response: 0.34, dampingFraction: 0.97),
                value: controller.liquidPinch
            )
    }

    private var bubbleContent: some View {
        Button {
            controller.redock()
        } label: {
            // Koyu, camlı zemin `blobMaterial`'dan geliyor — burada ikinci
            // bir daire dolgusu çizilmiyor; aynı yerde iki malzeme üst üste
            // binerse okunabilirlik bozulur (bkz. dosya başı not).
            ZStack {
                Image(systemName: "checklist")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)

                if activeTasks.count > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(.black, lineWidth: 1))
                        // Baloncuk gerçek Liquid Glass içinde çiziliyor —
                        // rozeti GPU'da ayrı, opak bir dokuya önceden çizip
                        // camın arkasındakiyle harmanlamasını tamamen engelle.
                        .compositingGroup()
                        .drawingGroup()
                        .offset(x: 18, y: -18)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: EdgePanelController.bubbleSize, height: EdgePanelController.bubbleSize)
        .contentShape(Circle())
        .accessibilityLabel(L10n.s("GlassDo Widget'ı", "GlassDo Widget", "Виджет GlassDo"))
        .accessibilityAddTraits(.isButton)
        // Konum tamamen `NSEvent.mouseLocation`'dan okunuyor (bkz.
        // `EdgePanelController.updateDrag`); jest yalnızca sürüklemenin
        // başladığını/bittiğini haber veriyor.
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { _ in
                    if !isDragging {
                        isDragging = true
                        controller.beginDrag()
                    }
                    controller.updateDrag()
                }
                .onEnded { _ in
                    isDragging = false
                    controller.endDrag()
                }
        )
    }
}
