import Observation

/// A window's status bar state, owned by its `DocumentWindowController` and read by
/// `DocumentView`. The items themselves read the document (`StatusBar`).
@MainActor
@Observable
final class StatusBarModel {
    /// Whether the window shows the status bar (restorable).
    var isVisible: Bool

    init(isVisible: Bool) {
        self.isVisible = isVisible
    }
}
