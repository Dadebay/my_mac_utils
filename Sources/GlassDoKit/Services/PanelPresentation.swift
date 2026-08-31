import Foundation

public enum PanelMode: String, Sendable, CaseIterable {
    case rail, sliver, pinned
}

public enum PanelVisualState: Equatable, Sendable {
    case rail, sliver, expanded
}

public enum PanelContent: Hashable, Sendable {
    case tasks, completed, folders, memory
    /// Sistem panosunun tek tek ray ikonu olarak yerleştirilebilen parçaları.
    case network, battery, disk, processor
}

public enum PanelPresentation {

    public static func shouldCollapseOnHoverExit(mode: PanelMode) -> Bool {
        mode != .pinned
    }

    public static func shouldAutoHideToSliver(mode: PanelMode, isExpanded: Bool) -> Bool {
        mode == .sliver && !isExpanded
    }
}
