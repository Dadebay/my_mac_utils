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
        // Ray cam kabın DIŞINDA: cam yüzey pencereyle birlikte büyürken
        // kabın içindeki her şey o büyümeye katılıyor ve ikon şeridi
        // sıfırdan açılıyormuş gibi görünüyordu. Cam yalnızca panel
        // gövdesini (ve rayın altındaki zemini) çiziyor; ikonlar üstte,
        // sabit genişlikte, ayrı bir katman.
        // Üç katman: rayın hep duran cam zemini, üzerine belirip kaybolan
        // panel gövdesi, en üstte ikonlar. Pencere hiç boyut
        // değiştirmediği ve gövde de genişlemediği için kımıldayan hiçbir
        // şey yok — hareketin tamamı sönümlenme.
        ZStack(alignment: shellAlignment) {
          railSurface

          if controller.visualState == .expanded {
            panelSurface
              .transition(.opacity)
          }

          rail
        }
        .animation(panelFadeAnimation, value: controller.visualState)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: shellAlignment)
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

  /// Gövdenin belirip kaybolma süresi. Açılış biraz daha uzun: boş bir
  /// yüzeyin dolması, dolu bir yüzeyin boşalmasından daha yavaş okunur.
  private var panelFadeAnimation: Animation? {
    if reduceMotion { return .easeOut(duration: 0.10) }
    return controller.visualState == .expanded
      ? .easeOut(duration: EdgeTokens.panelExpandDuration * 0.7)
      : .easeOut(duration: EdgeTokens.panelCollapseDuration * 0.7)
  }

  /// Rayın altındaki cam. Her zaman orada: panel kapanınca ikonlar
  /// zeminsiz kalmamalı.
  ///
  /// Köşe yalnızca panel kapalıyken yuvarlak. Ayarlardaki "köşe yarıçapı"
  /// kapalı hâlde gördüğünüz tek yüzey bu olduğu için buraya da uygulanmak
  /// zorunda. Panel açıkken yuvarlaklık gövdenin kendi yüzeyine geçiyor;
  /// ray da orada kare kalıyor, aksi halde iki yüzeyin birleştiği yerde
  /// içeri doğru bir çentik açılıyordu.
  private var railSurface: some View {
    Color.clear
      .frame(width: CGFloat(railWidth))
      .frame(maxHeight: .infinity)
      .adaptiveGlassShell(
        edge: controller.edge,
        cornerRadius: controller.visualState == .expanded ? 0 : CGFloat(cornerRadius)
      )
  }

  /// Panel gövdesi ve kendi cam yüzeyi. Rayın yanında duruyor, onun
  /// altına girmiyor; köşeleri yalnızca ekranın içine bakan tarafta.
  private var panelSurface: some View {
    panelContentHost
      .frame(maxHeight: .infinity, alignment: .top)
      .adaptiveGlassShell(edge: controller.edge, cornerRadius: CGFloat(cornerRadius))
      .padding(controller.edge == .trailing ? .trailing : .leading, CGFloat(railWidth))
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
      // Ray tek bir katman olarak birleştiriliyor: pencere boyutu her
      // karede değişirken alt görünümlerin tek tek yeniden kompozisyonu
      // ikonlarda titremeye yol açıyordu.
      .compositingGroup()
  }

  @ViewBuilder
  private var panelContent: some View {
    switch controller.content {
    case .tasks:
      PanelTaskListView(showCompleted: false)
    case .completed:
      PanelTaskListView(showCompleted: true)
    case .folders:
      PanelShelfView()
    case .memory:
      PanelMemoryView()
    case .clipboard:
      PanelClipboardView()
    case .network:
      PanelSystemStatView(metric: .network)
    case .battery:
      PanelSystemStatView(metric: .battery)
    case .disk:
      PanelSystemStatView(metric: .disk)
    case .processor:
      PanelSystemStatView(metric: .processor)
    case .volume:
      ScrollView {
        PanelVolumeMixerView()
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
      }
      .frame(
        width: PanelSettings.panelWidth,
        height: PanelSettings.effectivePanelHeight,
        alignment: .top
      )
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
    // Genişlik sabit: pencere hep açık boyutunda durduğu için `infinity`
    // kapalı hâlde bile bütün alanı kaplardı. Sabit genişlik ayrıca
    // açılırken metinlerin yeniden satırlanmasını da önlüyor.
    .frame(width: PanelSettings.panelWidth, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .clipped()
    .animation(contentSwapAnimation, value: controller.content)
  }
}
