import AppKit
import PeepCore

/// Content width (#37, per window since #47). View > Content Width picks this window's preset
/// (`contentWidth`); a new window starts with Settings' default (`ContentWidthSettings`). The
/// page's user layer is swapped in place, keeping the reading position, and window restoration
/// keeps the preset.
extension DocumentWindowController {
    /// The restorable-state key for the window's preset (a `ContentWidth` raw value, always
    /// written; absent only in state saved before #47, which then keeps Settings' default).
    static let contentWidthStateKey = "peepContentWidth"

    /// Starts pages with the window's width. Called once from `init`, before the first load.
    func installContentWidth() {
        coordinator.userStyle = UserStyle(contentWidth: contentWidth)
    }

    /// Sets this window's preset. Other windows and the default for new windows don't change.
    func setContentWidth(to width: ContentWidth) {
        guard width != contentWidth else {
            return
        }
        contentWidth = width
        applyUserStyle()
        window?.invalidateRestorableState()
    }

    /// Applies `contentWidth`: pages loaded from now on start with it, and the loaded page is
    /// updated in place. A load already under way applies it when it finishes
    /// (`WebViewCoordinator.load`); live reload swaps only the body, so the style stays.
    private func applyUserStyle() {
        coordinator.userStyle = UserStyle(contentWidth: contentWidth)
        Task { [coordinator] in
            // Fails only without a page to update (the web content process exited); the reload
            // that follows starts with `userStyle`.
            try? await coordinator.applyUserStyleToPage()
        }
    }

    // MARK: Actions

    /// View > Content Width > (preset). The item's `representedObject` is the preset's raw value.
    @objc func setContentWidth(_ sender: Any?) {
        guard let rawValue = (sender as? NSMenuItem)?.representedObject as? String,
            let width = ContentWidth(rawValue: rawValue)
        else {
            return
        }
        setContentWidth(to: width)
    }

    /// Checks this window's preset.
    func validateContentWidthItem(_ menuItem: NSMenuItem) -> Bool {
        let rawValue = menuItem.representedObject as? String
        menuItem.state = rawValue == contentWidth.rawValue ? .on : .off
        return true
    }

    // MARK: Restoration

    func encodeContentWidthState(with coder: NSCoder) {
        coder.encode(contentWidth.rawValue as NSString, forKey: Self.contentWidthStateKey)
    }

    /// Restores the preset. Restorable state is untrusted input: anything but a preset's raw
    /// value is ignored.
    func restoreContentWidthState(with coder: NSCoder) {
        guard let rawValue = coder.decodeObject(of: NSString.self, forKey: Self.contentWidthStateKey) as String?,
            let width = ContentWidth(rawValue: rawValue)
        else {
            return
        }
        setContentWidth(to: width)
    }
}
