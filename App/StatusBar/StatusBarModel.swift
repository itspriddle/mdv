import Observation

/// A window's status bar state, owned by its `DocumentWindowController` and read by
/// `DocumentView`. The items themselves read the document (`StatusBar`).
@MainActor
@Observable
final class StatusBarModel {
    /// Whether the window shows the status bar (restorable).
    var isVisible: Bool
    /// Whether the window shows the outline, for the outline toggle's on state. The window
    /// controller keeps it in step with the sidebar (`DocumentWindowController.isOutlineVisible`).
    var isOutlineVisible: Bool

    init(isVisible: Bool, isOutlineVisible: Bool = false) {
        self.isVisible = isVisible
        self.isOutlineVisible = isOutlineVisible
    }
}
