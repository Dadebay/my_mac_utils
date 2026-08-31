import SwiftUI
import GlassDoKit

/// Ayarlar değişirken rail'in gerçek görünümünü canlı gösterir.
/// Panel controller'a bağlı değil — doğrudan @AppStorage okur.
struct RailPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PanelSettings.railWidthKey) private var railWidth = PanelSettings.defaultRailWidth
    @AppStorage(PanelSettings.iconScaleKey) private var iconScale = PanelSettings.defaultIconScale
    @AppStorage(PanelSettings.cornerRadiusKey) private var cornerRadius = PanelSettings.defaultCornerRadius
    @AppStorage(PanelSettings.selectedIconCornerRadiusKey) private var selectedCorner = PanelSettings.defaultSelectedIconCornerRadius
    @AppStorage(PanelSettings.selectedIconPaddingKey) private var selectedIconPadding = PanelSettings.defaultSelectedIconPadding
    @AppStorage(PanelSettings.panelWidthKey) private var panelWidth = PanelSettings.defaultPanelWidth
    @AppStorage(PanelSettings.panelHeightKey) private var panelHeight = PanelSettings.defaultPanelHeight

    @AppStorage(PanelSettings.showTasksIconKey) private var showTasks = true
    @AppStorage(PanelSettings.showAddIconKey) private var showAdd = true
    @AppStorage(PanelSettings.showCompletedIconKey) private var showCompleted = true
    @AppStorage(PanelSettings.showFoldersIconKey) private var showFolders = true
    @AppStorage(PanelSettings.showMemoryIconKey) private var showMemory = true
    @AppStorage(PanelSettings.showNetworkIconKey) private var showNetwork = false
    @AppStorage(PanelSettings.showBatteryIconKey) private var showBattery = false
    @AppStorage(PanelSettings.showDiskIconKey) private var showDisk = false
    @AppStorage(PanelSettings.showProcessorIconKey) private var showProcessor = false
    @AppStorage(PanelSettings.showPinIconKey) private var showPin = true
    @AppStorage(PanelSettings.showWindowSwitcherIconKey) private var showWindowSwitcher = true
    @AppStorage(PanelSettings.showSettingsIconKey) private var showSettings = true

    /// Önizleme gerçek boyutun bu oranında çizilir.
    private let scale: CGFloat = 0.62

    private var icons: [String] {
        var result: [String] = []
        if showTasks { result.append("checklist") }
        if showAdd { result.append("plus") }
        if showCompleted { result.append("checkmark.circle") }
        if showFolders { result.append("folder") }
        if showMemory { result.append("memorychip") }
        if showNetwork { result.append("globe") }
        if showBattery { result.append("battery.100percent") }
        if showDisk { result.append("internaldrive") }
        if showProcessor { result.append("cpu") }
        if showPin { result.append("pin") }
        if showWindowSwitcher { result.append("rectangle.on.rectangle") }
        if showSettings { result.append("gear") }
        return result
    }

    /// Gerçek uygulamanın kendi ray yüksekliği formülüyle aynı (bkz.
    /// `PanelSettings.railHeight`) — görünür ikon sayısına göre değişir.
    /// Önceden sabit 160pt'e kırpılıyordu, bu da 6 ikonla üstteki rozetin
    /// (ve altındaki içeriğin) kesilmesine yol açıyordu.
    private var panelSheetHeight: CGFloat {
        max(min(CGFloat(panelHeight) * scale, 160), PanelSettings.railHeight * scale)
    }

    private var previewHeight: CGFloat { panelSheetHeight + 28 }

    private var iconTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.96))
    }

    private var iconAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : Motion.iconVisibility
    }

    var body: some View {
        ZStack {
            wallpaper

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                panelSheet
                    .padding(.trailing, 0)
            }
            .padding(.vertical, 14)
        }
        .frame(height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    /// Cam etkisinin okunabilirliğini göstermek için renkli bir zemin.
    private var wallpaper: some View {
        LinearGradient(
            colors: [
                Color(red: 0.22, green: 0.45, blue: 0.68),
                Color(red: 0.35, green: 0.58, blue: 0.72),
                Color(red: 0.55, green: 0.62, blue: 0.55),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var panelSheet: some View {
        HStack(spacing: 0) {
            // Genişlemiş panel gövdesi (içerik yer tutucu)
            VStack(alignment: .leading, spacing: 5 * scale) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.85))
                    .frame(width: 62 * scale, height: 7 * scale)
                    .padding(.bottom, 3 * scale)
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 5 * scale) {
                        Circle()
                            .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                            .frame(width: 8 * scale, height: 8 * scale)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.28))
                            .frame(width: (110 - CGFloat(i * 16)) * scale, height: 6 * scale)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10 * scale)
            .frame(
                width: CGFloat(panelWidth) * scale,
                height: panelSheetHeight,
                alignment: .topLeading
            )

            railStrip
        }
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: CGFloat(cornerRadius) * scale,
                bottomLeadingRadius: CGFloat(cornerRadius) * scale,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black.opacity(0.8))
        }
        .frame(height: panelSheetHeight, alignment: .top)
    }

    private var railStrip: some View {
        VStack(spacing: 0) {
            ForEach(Array(icons.enumerated()), id: \.element) { index, name in
                let isActive = index == 0
                ZStack {
                    RoundedRectangle(cornerRadius: CGFloat(selectedCorner) * scale, style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.9) : .clear)
                        .frame(
                            width: max(EdgeTokens.railIconHitSize * CGFloat(iconScale) * scale - CGFloat(selectedIconPadding) * 2 * scale, 4 * scale),
                            height: max(EdgeTokens.railIconHitSize * CGFloat(iconScale) * scale - CGFloat(selectedIconPadding) * 2 * scale, 4 * scale)
                        )

                    Image(systemName: name)
                        .font(.system(size: 17 * CGFloat(iconScale) * scale))
                        .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.85))

                    if index == 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 9 * scale, height: 9 * scale)
                            .overlay(Circle().strokeBorder(.black, lineWidth: 0.7))
                            .offset(x: 11 * scale, y: -11 * scale)
                    }
                }
                .frame(height: EdgeTokens.railRowHeight * scale)
                .transition(iconTransition)
            }
        }
        .animation(iconAnimation, value: icons)
        .frame(width: CGFloat(railWidth) * scale)
        .padding(.vertical, 16 * scale)
    }
}
