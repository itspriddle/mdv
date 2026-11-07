import AppKit
import MdvCore

/// Content width (#37). View > Content Width picks the app-wide preset (`ContentWidthSettings`,
/// persisted), and every window follows it live: the page's user layer is swapped in place,
/// keeping the reading position.
extension DocumentWindowController {
    /// Starts pages with the app-wide width and follows its changes. Called once from `init`,
    /// before the first load.
    func installContentWidth() {
        coordinator.userStyle = contentWidthSettings.userStyle
        NotificationCenter.default.addObserver(
            self, selector: #selector(contentWidthSettingsDidChange(_:)),
            name: ContentWidthSettings.didChangeNotification, object: contentWidthSettings)
    }

    @objc private func contentWidthSettingsDidChange(_ notification: Notification) {
        applyUserStyle()
    }

    /// Applies the current settings: pages loaded from now on start with them, and the loaded
    /// page is updated in place. A load already under way applies them when it finishes
    /// (`WebViewCoordinator.load`); live reload swaps only the body, so the style stays.
    private func applyUserStyle() {
        coordinator.userStyle = contentWidthSettings.userStyle
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
        contentWidthSettings.width = width
    }

    /// Checks the current preset.
    func validateContentWidthItem(_ menuItem: NSMenuItem) -> Bool {
        let rawValue = menuItem.representedObject as? String
        menuItem.state = rawValue == contentWidthSettings.width.rawValue ? .on : .off
        return true
    }
}
