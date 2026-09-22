import Foundation

public enum PanelMode: String, Sendable, CaseIterable {
    case rail, sliver, pinned
}

public enum PanelVisualState: Equatable, Sendable {
    case rail, sliver, expanded
}

public enum PanelContent: Hashable, Sendable {
    case tasks, completed, folders, memory
    /// Kopyalanan metin/görsellerin geçmişi.
    case clipboard
    /// Sistem panosunun tek tek ray ikonu olarak yerleştirilebilen parçaları.
    case network, battery, disk, processor
    /// Ses çıkışı/girişi ve o an ses çalan uygulamalar.
    case volume
}

public enum PanelPresentation {

    public static func shouldCollapseOnHoverExit(mode: PanelMode) -> Bool {
        mode != .pinned
    }

    public static func shouldAutoHideToSliver(mode: PanelMode, isExpanded: Bool) -> Bool {
        mode == .sliver && !isExpanded
    }
}
