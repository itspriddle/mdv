import AppKit
import MdvCore

/// The window's theme (#34): View > Theme and the toolbar's theme menu pick it, the switch is
/// in place (`WebViewCoordinator.show(_:)`, no reload), and window restoration keeps it.
///
/// The window shows `themeSettings.registry.theme(id: themeID)`, so an unknown or removed id
/// (a deleted custom theme, #35) falls back to the registry's default, and a custom theme
/// whose CSS changed is swapped in when the registry is replaced.
extension DocumentWindowController {
    static let themeToolbarItem = NSToolbarItem.Identifier("theme")

    /// The restorable-state key for the picked theme's id (a `String`).
    static let themeStateKey = "mdvTheme"

    /// The theme the window shows.
    var theme: Theme { coordinator.theme }

    /// Applies the window's theme and follows registry changes. Called once from `init`.
    func installTheme() {
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeSettingsDidChange(_:)), name: ThemeSettings.didChangeNotification,
            object: themeSettings)
    }

    @objc private func themeSettingsDidChange(_ notification: Notification) {
        applyTheme()
    }

    /// Shows the theme with `id` in this window. Doesn't change the default for new windows,
    /// which only Settings (#36) sets.
    func setTheme(id: String) {
        guard id != themeID else {
            return
        }
        themeID = id
        applyTheme()
        window?.invalidateRestorableState()
    }

    /// Resolves `themeID` in the registry and shows the result: window background, under-page
    /// area, and the page (swapped in place). Does nothing when it is already shown.
    func applyTheme() {
        let theme = themeSettings.registry.theme(id: themeID)
        window?.backgroundColor = .themeBackground(theme.background)
        coordinator.show(theme)
    }

    // MARK: Actions

    /// View > Theme > <theme> and the toolbar's theme menu: the sender's `representedObject` is
    /// the theme id. Only this window changes; the theme for new windows is Settings' (#36).
    @objc func selectTheme(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String,
            themeSettings.registry.contains(id: id)
        else {
            return
        }
        setTheme(id: id)
    }

    /// Checks the item of the theme the window shows.
    func validateThemeItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = (menuItem.representedObject as? String) == theme.id ? .on : .off
        return true
    }

    /// The toolbar's theme menu: the same items as View > Theme.
    func makeThemeToolbarItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: Self.themeToolbarItem)
        item.label = "Theme"
        item.paletteLabel = "Theme"
        item.toolTip = "Choose the window’s theme"
        item.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Theme")
        item.showsIndicator = true
        item.menu = ThemeMenu.makeMenu(settings: themeSettings)
        return item
    }

    // MARK: Restoration

    func encodeThemeState(with coder: NSCoder) {
        coder.encode(themeID as NSString, forKey: Self.themeStateKey)
    }

    /// Restores the picked theme. Restorable state is untrusted input: anything but a short
    /// string is ignored, and an id that isn't registered shows the default theme.
    func restoreThemeState(with coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSString.self, forKey: Self.themeStateKey) as String?,
            Self.isPlausibleThemeID(id)
        else {
            return
        }
        setTheme(id: id)
    }

    /// Whether `id` could be a theme id: non-empty and at most 256 characters.
    nonisolated static func isPlausibleThemeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 256
    }
}
