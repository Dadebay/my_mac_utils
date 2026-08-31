import GlassDoKit
import SwiftData
import SwiftUI

struct EdgeRailView: View {
  @Environment(EdgePanelController.self) private var controller
  @Environment(WindowSwitcherController.self) private var switcherController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Query(filter: Task.activePredicate()) private var activeTasks: [Task]
  @Namespace private var selectionNamespace
  @State private var isDragging = false
  @AppStorage(PanelSettings.railWidthKey) private var railWidth = Double(EdgeTokens.railWidth)

  @AppStorage(PanelSettings.showTasksIconKey) private var showTasksIcon = true
  @AppStorage(PanelSettings.showAddIconKey) private var showAddIcon = true
  @AppStorage(PanelSettings.showCompletedIconKey) private var showCompletedIcon = true
  @AppStorage(PanelSettings.showFoldersIconKey) private var showFoldersIcon = true
  @AppStorage(PanelSettings.showMemoryIconKey) private var showMemoryIcon = true
  @AppStorage(PanelSettings.showNetworkIconKey) private var showNetworkIcon = false
  @AppStorage(PanelSettings.showBatteryIconKey) private var showBatteryIcon = false
  @AppStorage(PanelSettings.showDiskIconKey) private var showDiskIcon = false
  @AppStorage(PanelSettings.showProcessorIconKey) private var showProcessorIcon = false
  @AppStorage(PanelSettings.showPinIconKey) private var showPinIcon = true
  @AppStorage(PanelSettings.showSettingsIconKey) private var showSettingsIcon = true
  @AppStorage(PanelSettings.showWindowSwitcherIconKey) private var showWindowSwitcherIcon = true

  private var iconVisibility: [Bool] {
    [
      showTasksIcon, showAddIcon, showCompletedIcon, showFoldersIcon,
      showMemoryIcon, showNetworkIcon, showBatteryIcon, showDiskIcon,
      showProcessorIcon, showPinIcon, showWindowSwitcherIcon, showSettingsIcon,
    ]
  }

  private var iconTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .opacity.combined(with: .scale(scale: 0.96))
  }

  private var iconAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.12) : Motion.iconVisibility
  }

  var body: some View {
    VStack(spacing: 0) {
      if showTasksIcon {
        RailIconButton(
          systemName: "checklist", badge: activeTasks.count, isActive: controller.content == .tasks,
          selectionNamespace: selectionNamespace,
          action: { controller.selectContent(.tasks) }
        )
        .transition(iconTransition)
      }
      if showAddIcon {
        RailIconButton(
          systemName: "plus", selectionNamespace: selectionNamespace,
          action: { controller.selectContent(.tasks) }
        )
        .transition(iconTransition)
      }
      if showCompletedIcon {
        RailIconButton(
          systemName: "checkmark.circle", isActive: controller.content == .completed,
          selectionNamespace: selectionNamespace,
          action: { controller.selectContent(.completed) }
        )
        .transition(iconTransition)
      }
      if showFoldersIcon {
        RailIconButton(
          systemName: "folder", isActive: controller.content == .folders,
          selectionNamespace: selectionNamespace,
          action: { controller.selectContent(.folders) }
        )
        .transition(iconTransition)
      }
      if showMemoryIcon {
        RailIconButton(
          systemName: "memorychip", isActive: controller.content == .memory,
          selectionNamespace: selectionNamespace,
          action: { controller.selectContent(.memory) }
        )
        .transition(iconTransition)
      }
      if showNetworkIcon {
        RailIconButton(
          systemName: "globe", isActive: controller.content == .network,
          selectionNamespace: selectionNamespace,
          action: { controller.selectContent(.network) }
        )
        .transition(iconTransition)
      }
      if showBatteryIcon {
        RailIconButton(
          systemName: "battery.100percent", isActive: controller.content == .battery,
          selectionNamespace: selectionNamespace,
          action: { controller.selectContent(.battery) }
        )
        .transition(iconTransition)
      }
      if showDiskIcon {
        RailIconButton(
          systemName: "internaldrive", isActive: controller.content == .disk,
          selectionNamespace: selectionNamespace,
          action: { controller.selectContent(.disk) }
        )
        .transition(iconTransition)
      }
      if showProcessorIcon {
        RailIconButton(
          systemName: "cpu", isActive: controller.content == .processor,
          selectionNamespace: selectionNamespace,
          action: { controller.selectContent(.processor) }
        )
        .transition(iconTransition)
      }
      if showPinIcon {
        RailIconButton(
          systemName: controller.mode == .pinned ? "pin.fill" : "pin",
          isActive: controller.mode == .pinned,
          selectionID: "rail-pin-selection", selectionNamespace: selectionNamespace,
          action: {
            controller.setMode(controller.mode == .pinned ? .rail : .pinned)
            UsageStore.track(.pinMode, source: .edgeRail)
          }
        )
        .transition(iconTransition)
      }
      if showWindowSwitcherIcon {
        RailIconButton(
          systemName: "rectangle.on.rectangle", selectionNamespace: selectionNamespace,
          action: { switcherController.toggleSummon() }
        )
        .transition(iconTransition)
      }
      if showSettingsIcon {
        RailIconButton(
          systemName: "gear", selectionNamespace: selectionNamespace,
          action: { controller.openSettings?() }
        )
        .transition(iconTransition)
      }
    }
    .animation(iconAnimation, value: iconVisibility)
    .frame(width: railWidth)
    // `PanelSettings.railHeight` bu 16 + ikonlar + 16 formülüyle
    // hesaplanıyor. Görünümde padding olmayınca dar kabuk pencerenin
    // içinde ortalanıyor, açık kabuk ise yüksekliği tamamen dolduruyor;
    // sonuçta açılışta bütün ray yaklaşık 16 pt yer değiştiriyordu.
    .padding(.vertical, 16)
    .overlay(alignment: .top) {
      dragHandle
    }
    .accessibilityElement(children: .contain)
  }

  /// Sürükleme yalnızca üstteki tutamaktan başlar. Önceki sürüm jesti bütün
  /// ray üzerine koyduğu için Button'ın press jestiyle yarışıyor, küçük fare
  /// hareketlerinde tıklamayı yutup açık widget'ı ekranda bırakabiliyordu.
  private var dragHandle: some View {
    Capsule(style: .continuous)
      .fill(isDragging ? Color.white.opacity(0.42) : Color.white.opacity(0.18))
      .frame(width: 18, height: 3)
      .frame(maxWidth: .infinity)
      .frame(height: 16)
      .contentShape(Rectangle())
      .help(L10n.s("Paneli taşı", "Move panel", "Переместить панель"))
      .gesture(
        DragGesture(minimumDistance: 4)
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
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragging)
  }
}
