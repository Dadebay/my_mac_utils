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
