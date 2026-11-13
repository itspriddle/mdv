import AppKit

/// The status bar along the bottom of the window (`StatusBar`), shown or hidden from the View
/// menu.
extension DocumentWindowController {
    /// The restorable-state key for the status bar's visibility (a `Bool`), saved by
    /// `DocumentWindow` with the window's own state.
    static let statusBarVisibleStateKey = "peepStatusBarVisible"

    /// Whether this window shows the status bar. Window restoration can save and set this;
    /// setting it doesn't change the default for new windows (`StatusBarPreference`).
    var isStatusBarVisible: Bool {
        get { statusBar.isVisible }
        set {
            statusBar.isVisible = newValue
            window?.invalidateRestorableState()
        }
    }

    /// View > Show/Hide Status Bar. The choice becomes the default for new windows.
    @objc func toggleStatusBar(_ sender: Any?) {
        let visible = !isStatusBarVisible
        isStatusBarVisible = visible
        statusBarPreference.showsStatusBarInNewWindows = visible
    }

    func validateStatusBarItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.title = isStatusBarVisible ? "Hide Status Bar" : "Show Status Bar"
        return true
    }

    func encodeStatusBarState(with coder: NSCoder) {
        coder.encode(isStatusBarVisible, forKey: Self.statusBarVisibleStateKey)
    }

    func restoreStatusBarState(with coder: NSCoder) {
        if coder.containsValue(forKey: Self.statusBarVisibleStateKey) {
            isStatusBarVisible = coder.decodeBool(forKey: Self.statusBarVisibleStateKey)
        }
    }
}
