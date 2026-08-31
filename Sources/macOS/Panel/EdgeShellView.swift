import GlassDoKit
import SwiftUI

struct EdgeShellView: View {
  @Environment(EdgePanelController.self) private var controller
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var glassNS
  @AppStorage(PanelSettings.cornerRadiusKey) private var cornerRadius = 22.0
  @AppStorage(PanelSettings.railWidthKey) private var railWidth = Double(EdgeTokens.railWidth)

  /// Kabuk yatay olarak açılırken içerik yalnızca kısa bir fade ile gelir.
  /// Ek scale, pencere boyut animasyonuyla birleşince çift hareket gibi
  /// görünüyordu.
  private var appearAnimation: Animation? {
    reduceMotion ? .easeOut(duration: 0.12) : Motion.panelContentAppearance
  }

  private var disappearAnimation: Animation? {
    reduceMotion ? .easeOut(duration: 0.10) : Motion.panelContentDisappearance
  }

  private var contentTransition: AnyTransition {
    return .asymmetric(
      insertion: .opacity.animation(appearAnimation),
      removal: .opacity.animation(disappearAnimation)
    )
  }

  /// Panel zaten açıkken bir rail ikonundan diğerine geçerken kullanılır.
  /// Yukarıdaki `contentTransition`'dan ayrı: panel çerçevesi hiç
  /// oynamıyor, yalnız içerik slotu kısa bir opacity ile değişiyor.
  private var contentSwapAnimation: Animation? {
    reduceMotion ? .easeOut(duration: 0.10) : Motion.panelContentSwapIn
  }

  private var contentSwapTransition: AnyTransition {
    .asymmetric(
      insertion: .opacity.animation(
        reduceMotion ? .easeOut(duration: 0.10) : Motion.panelContentSwapIn
      ),
      removal: .opacity.animation(
        reduceMotion ? .easeOut(duration: 0.10) : Motion.panelContentSwapOut
      )
    )
  }

  var body: some View {
    Group {
      if controller.isDocked {
        GlassEffectContainer(spacing: 0) {
          shellContent
            // Dar ve açık durumda cam yüzey pencerenin tamamını
            // doldurur. İçeriğin ideal yüksekliğine göre AppKit
            // frame'i içinde yeniden hizalanmasını engeller.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .adaptiveGlassShell(edge: controller.edge, cornerRadius: CGFloat(cornerRadius))
            .glassEffectID("shell", in: glassNS)
        }
      } else {
        LiquidBubbleView()
      }
    }
    // Yalnızca sliver → rail geri dönüşü için hover kullanılıyor.
    // İçerik açma/kapama tamamen tıklamayla — hover asla panel açmaz.
    .onHover { inside in
      if inside { controller.reveal() }
    }
    // Panel her zaman koyu — arka plan sabit siyah olduğu için tema
    // ayarından bağımsız, metin/ikon kontrastı hep doğru olsun.
    .preferredColorScheme(.dark)
  }

  private var shellContent: some View {
    // İçerik ve ray ayrı katmanlarda: panel kapanırken geniş HStack'in
    // trailing konumu ray üzerinde kalıp ikonları sağa itmesin.
    ZStack(alignment: shellAlignment) {
      panelLayout
      rail
    }
  }

  private var shellAlignment: Alignment {
    controller.edge == .leading ? .topLeading : .topTrailing
  }

  private var panelLayout: some View {
    HStack(alignment: .top, spacing: 0) {
      if controller.edge == .leading {
        railPlaceholder
        if controller.visualState == .expanded {
          panelContentHost.transition(contentTransition)
        }
      } else {
        if controller.visualState == .expanded {
          panelContentHost.transition(contentTransition)
        }
        railPlaceholder
      }
    }
  }

  private var railPlaceholder: some View {
    Color.clear
      .frame(width: CGFloat(railWidth))
      .allowsHitTesting(false)
  }

  private var rail: some View {
    EdgeRailView()
      .id("edge-rail")
      .frame(width: CGFloat(railWidth), alignment: .center)
      // İçerik değişirken/scroll olurken panel katmanı rayın hit-test
      // alanının önüne geçmesin. Ray her zaman üstte ve etkileşimli.
      .zIndex(2)
      // Panel açılıp kapanırken ray sabit kalır; ikon görünürlük
      // ayarlarının kendi yerel animasyonu ise çalışmaya devam eder.
      .animation(nil, value: controller.visualState)
  }

  @ViewBuilder
  private var panelContent: some View {
    switch controller.content {
    case .tasks:
      PanelTaskListView(showCompleted: false)
    case .completed:
      PanelTaskListView(showCompleted: true)
    case .folders:
      PanelFolderShelfView()
    case .memory:
      PanelMemoryView()
    case .network:
      PanelSystemStatView(metric: .network)
    case .battery:
      PanelSystemStatView(metric: .battery)
    case .disk:
      PanelSystemStatView(metric: .disk)
    case .processor:
      PanelSystemStatView(metric: .processor)
    }
  }

  /// Panel açıkken ikonlar arası geçişi barındıran kalıcı slot. `.tasks`
  /// ve `.completed` aynı `PanelTaskListView` tipini paylaştığı için
  /// `.id(controller.content)` olmadan SwiftUI bunu yeni bir sayfa değil,
  /// var olan görünümün özellik güncellemesi sayar — geçiş hiç tetiklenmez.
  private var panelContentHost: some View {
    ZStack(alignment: .topLeading) {
      panelContent
        .id(controller.content)
        .transition(contentSwapTransition)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .clipped()
    .animation(contentSwapAnimation, value: controller.content)
  }
}
