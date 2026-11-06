import GlassDoKit
import SwiftUI

struct RailIconButton: View {
  let systemName: String
  var badge: Int? = nil
  var isActive: Bool = false
  var selectionID = "rail-content-selection"
  let selectionNamespace: Namespace.ID
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovering = false
  /// Simgenin ne kadarının göründüğü, 0…1 (soldan sağa). Seçilince 0'a
  /// atılıp 1'e animasyonla dönüyor.
  @State private var reveal: CGFloat = 1
  @AppStorage(PanelSettings.iconScaleKey) private var iconScale = 1.0
  @AppStorage(PanelSettings.selectedIconCornerRadiusKey) private var selectedCornerRadius = 10.0
  @AppStorage(PanelSettings.selectedIconPaddingKey) private var selectedIconPadding = PanelSettings.defaultSelectedIconPadding

  /// Ayarlardaki küçük ikon ölçeği tıklama hedefini küçültmemeli. Sembol
  /// görsel olarak ölçeklenir ama hit target macOS'ta rahat bir 34 pt kalır.
  private var hitSize: CGFloat { max(34, EdgeTokens.railIconHitSize * iconScale) }
  private var fontSize: CGFloat { 17 * iconScale }
  /// Vurgu şekli tıklama hedefinin tamamını değil, ondan bu kadar içeri
  /// çekilmiş bir alanı dolduruyor.
  private var highlightSize: CGFloat { max(hitSize - selectedIconPadding * 2, 4) }

  /// Seçim vurgusunun kendi animasyonu — yalnız bu düğmenin `isActive`
  /// değişimine bağlı. Rail'in tamamına uygulanan eski global animasyon,
  /// içerik geçişindeki opacity fade'ini de aynı transaction'a sokup
  /// ikonları zıplatıyordu.
  /// Hareket azaltma açıkken simge sabit kalıyor: büyüme ölçek hareketi,
  /// belirme de ikisi gibi gözü çeken bir hareket.
  ///
  /// %15: ilk deneme %8'di, 17 punto bir simgede bu 1,4 punto — ölçümde
  /// hareket vardı ama gözle fark edilmiyordu.
  private var hoverScale: CGFloat {
    isHovering && !isActive && !reduceMotion ? 1.15 : 1
  }

  /// Kenarı yumuşak, soldan sağa süpüren bir bant. Sert kenarlı bir
  /// dikdörtgen simgeyi bıçakla kesiyormuş gibi açardı.
  ///
  /// Bant `W + F` genişliğinde (W simge, F=0,35·W yumuşak kenar): ilk W
  /// kısmı dolu, son F kısmı saydamlaşıyor. Sağ ucu `reveal·(W+F)`
  /// konumunda ilerliyor, yani `reveal` 0 iken bütünüyle simgenin solunda
  /// (hiçbir şey görünmüyor), 1 iken dolu kısım tam simgenin üstünde
  /// (hepsi görünüyor) ve sınır 0…1 arasında simge boyunca doğrusal
  /// ilerliyor.
  ///
  /// İlk sürüm 1,5·W'lik bantla simgenin ancak son üçte birinde
  /// ilerliyordu: animasyon 400 ms sürse de görünen kısım ~100 ms'ydi
  /// (ölçüldü).
  private var revealMask: some View {
    GeometryReader { geo in
      let fade = geo.size.width * 0.35
      let band = geo.size.width + fade
      LinearGradient(
        stops: [
          .init(color: .black, location: 0),
          .init(color: .black, location: geo.size.width / band),
          .init(color: .clear, location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(width: band, height: geo.size.height)
      .offset(x: (reveal - 1) * band)
    }
  }

  private var selectionAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.10) : Motion.railSelection
  }

  var body: some View {
    Button(action: action) {
      ZStack {
        if isHovering && !isActive {
          RoundedRectangle(cornerRadius: selectedCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.09))
            .overlay {
              RoundedRectangle(cornerRadius: selectedCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .frame(width: highlightSize, height: highlightSize)
        }

        if isActive {
          selectionBackground
            .frame(width: highlightSize, height: highlightSize)
        }

        Image(systemName: systemName)
          .font(.system(size: fontSize))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(isActive ? Color.black.opacity(0.88) : Color.white.opacity(0.82))
          // Üzerine gelince %15 büyür. Seçili simge büyümüyor: zaten
          // beyaz zeminde, durumunu başka bir şey anlatıyor.
          .scaleEffect(hoverScale)
          .animation(Motion.railIconHover, value: isHovering)
          // Seçilince soldan sağa belirir: "bu artık açık" bilgisi vurgu
          // zemininin kaymasına ek olarak simgenin kendisinden de
          // okunuyor. Tek seferlik; sürekli dönen bir hareket her
          // zaman ekranda duran bir kontrolde yorucu olurdu.
          //
          // SF Symbols'ün kendi çizim efekti (`drawOn`) kullanılmıyor: o
          // yalnızca simgenin çizim verisi varsa oynuyor, rayda ise on
          // üç farklı simge var ve çoğu desteklemiyordu. Maske simgeden
          // bağımsız, hepsinde aynı çalışıyor.
          .mask { revealMask }

        if let badge, badge > 0 {
          Circle()
            .fill(Color.red)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(.black, lineWidth: 1))
            // Panel gerçek Liquid Glass içinde — camın kendisi
            // arkasındaki içeriği kırıp harmanlıyor, rozet dahil.
            // GPU'da ayrı, opak bir dokuya önceden çizip bu
            // etkiden tamamen çıkar (compositingGroup yetmedi).
            .compositingGroup()
            .drawingGroup()
            .offset(x: 11, y: -11)
        }
      }
      .animation(selectionAnimation, value: isActive)
      .frame(width: hitSize, height: hitSize)
      .contentShape(RoundedRectangle(cornerRadius: selectedCornerRadius, style: .continuous))
    }
    .buttonStyle(.pressScale(reduceMotion ? 1 : 0.96))
    .frame(height: EdgeTokens.railRowHeight)
    .contentShape(Rectangle())
    .onHover { isHovering = $0 }
    .onChange(of: isActive) { _, active in
      // Yalnızca seçilirken. Önce animasyonsuz sıfırlanıyor, sonra bir
      // sonraki turda animasyonla 1'e dönüyor: aynı işlemde yapılırsa 0
      // karesi hiç çizilmeden 1'e atlanırdı.
      guard active, !reduceMotion else { return }
      var reset = Transaction()
      reset.disablesAnimations = true
      withTransaction(reset) { reveal = 0 }
      DispatchQueue.main.async {
        withAnimation(Motion.railIconReveal) { reveal = 1 }
      }
    }
  }

  @ViewBuilder
  private var selectionBackground: some View {
    let shape = RoundedRectangle(cornerRadius: selectedCornerRadius, style: .continuous)
      .fill(Color.white.opacity(0.92))
      .shadow(color: .black.opacity(0.22), radius: 7, y: 2)

    if reduceMotion {
      shape.transition(.opacity)
    } else {
      shape.matchedGeometryEffect(id: selectionID, in: selectionNamespace)
    }
  }
}
