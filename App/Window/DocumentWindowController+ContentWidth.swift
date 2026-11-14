import AppKit
import PeepCore

/// Content width (#37, per window since #47). View > Content Width picks this window's preset
/// (`contentWidth`); a new window starts with Settings' default (`ContentWidthSettings`). The
/// page's user layer is swapped in place, keeping the reading position, and window restoration
/// keeps the preset. While Settings' custom width is on, it wins over every window's preset
/// (the window keeps its preset for when it goes off); open windows follow it live.
extension DocumentWindowController {
    /// The restorable-state key for the window's preset (a `ContentWidth` raw value, always
    /// written; absent only in state saved before #47, which then keeps Settings' default).
    static let contentWidthStateKey = "peepContentWidth"

    /// The View > Content Width item's `representedObject` for Settings' custom width.
    static let customContentWidthItemValue = "custom"

    /// The style pages get: the window's preset, unless Settings' custom width is on.
    var currentUserStyle: UserStyle {
        UserStyle(contentWidth: contentWidth, customWidth: contentWidthSettings.customWidth)
    }

    /// Starts pages with the window's width and follows Settings' custom width. Called once from
    /// `init`, before the first load.
    func installContentWidth() {
        coordinator.userStyle = currentUserStyle
        NotificationCenter.default.addObserver(
            self, selector: #selector(contentWidthSettingsDidChange(_:)),
            name: ContentWidthSettings.didChangeNotification, object: contentWidthSettings)
    }

    /// Settings changed: the custom width may have. A new default for new windows changes nothing.
    @objc private func contentWidthSettingsDidChange(_ notification: Notification) {
        guard coordinator.userStyle != currentUserStyle else {
            return
        }
        applyUserStyle()
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
        coordinator.userStyle = currentUserStyle
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

    /// Checks this window's preset. While Settings' custom width is on, its item (otherwise
    /// hidden, with the separator before it) is shown and checked, and the presets are disabled.
    func validateContentWidthItem(_ menuItem: NSMenuItem) -> Bool {
        let rawValue = menuItem.representedObject as? String
        let custom = contentWidthSettings.customWidth
        if rawValue == Self.customContentWidthItemValue {
            menuItem.isHidden = custom == nil
            menuItem.menu?.items.first { $0.isSeparatorItem }?.isHidden = custom == nil
            if let custom {
                menuItem.title = custom.displayName
            }
            menuItem.state = custom == nil ? .off : .on
            return false
        }
        menuItem.state = custom == nil && rawValue == contentWidth.rawValue ? .on : .off
        return custom == nil
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
