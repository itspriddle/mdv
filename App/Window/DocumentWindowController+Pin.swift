import AppKit

/// Pinned windows (Window > Pin Window, or the status bar's pin button): a pinned window floats
/// above other apps' windows. Pinned windows all float; among them, the one focused last is on
/// top (AppKit orders windows of one level by focus).
///
/// A pin belongs to the whole tab group: tabs share one frame, so a group with mixed levels
/// would jump between levels as the selected tab changes. Pinning a tab pins its siblings, and a
/// tab that joins a pinned group is pinned when it is first selected (`adoptTabGroupPin()`).
extension DocumentWindowController {
    /// The restorable-state key for the pin (a `Bool`), saved by `DocumentWindow` with the
    /// window's own state.
    static let pinnedStateKey = "peepPinned"

    /// Whether this window floats above other apps' windows. Window restoration can save and set
    /// this; setting it changes neither its tab siblings nor the default for new windows
    /// (`WindowPinPreference`).
    var isPinned: Bool {
        get { statusBar.isPinned }
        set {
            statusBar.isPinned = newValue
            window?.level = newValue ? .floating : .normal
            window?.invalidateRestorableState()
        }
    }

    /// Applies Settings' default and follows the window becoming key. Called once from `init`.
    func installPin() {
        isPinned = pinPreference.pinsNewWindows
        NotificationCenter.default.addObserver(
            self, selector: #selector(pinWindowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification,
            object: window)
    }

    @objc private func pinWindowDidBecomeKey(_ notification: Notification) {
        adoptTabGroupPin()
    }

    /// Window > Pin/Unpin Window and the status bar button: pins or unpins this window and every
    /// tab in its group.
    @objc func togglePinned(_ sender: Any?) {
        let pinned = !isPinned
        isPinned = pinned
        for controller in tabSiblingControllers {
            controller.isPinned = pinned
        }
    }

    /// Pins this window if another tab in its group is pinned: it joined a pinned group (a
    /// drop, a link, automatic tabbing, Merge All Windows, or a dragged tab). Tabs that aren't
    /// selected are off screen, so becoming key (selected) is soon enough; opening a tab in
    /// code also calls this directly.
    func adoptTabGroupPin() {
        if !isPinned, tabSiblingControllers.contains(where: \.isPinned) {
            isPinned = true
        }
    }

    /// The document window controllers of the other tabs in this window's group.
    private var tabSiblingControllers: [DocumentWindowController] {
        (window?.tabbedWindows ?? []).compactMap { tab in
            tab === window ? nil : tab.windowController as? DocumentWindowController
        }
    }

    func validatePinItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.title = isPinned ? "Unpin Window" : "Pin Window"
        return true
    }

    func encodePinState(with coder: NSCoder) {
        coder.encode(isPinned, forKey: Self.pinnedStateKey)
    }

    func restorePinState(with coder: NSCoder) {
        if coder.containsValue(forKey: Self.pinnedStateKey) {
            isPinned = coder.decodeBool(forKey: Self.pinnedStateKey)
        }
    }
}
