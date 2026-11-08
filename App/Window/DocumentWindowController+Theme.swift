import AppKit
import MdvCore

/// The window's theme (#34, #54): View > Theme picks it, the switch is in place
/// (`WebViewCoordinator.show(_:)`, no reload), and window restoration keeps the pick.
///
/// Precedence, highest first (`themeID`):
/// 1. the reader's pick for this window (`pickedThemeID`, View > Theme);
/// 2. the document's frontmatter theme (`documentThemeID`, `mdv.theme`, #54);
/// 3. Settings' default when the window opened (`newWindowThemeID`).
///
/// The window shows `themeSettings.theme(forWindowThemeID: themeID)`: an unknown or removed id
/// (a deleted or broken custom theme, #35, or a frontmatter id that isn't registered) falls back
/// to Settings' default theme (#45), and a custom theme whose CSS changed is swapped in when the
/// registry is replaced. The ids are kept, so the theme comes back when its file does.
/// Restoration saves only the pick, so a frontmatter theme edited while the app was closed takes
/// effect on relaunch. A live reload that changes `mdv.theme` swaps the theme in place.
extension DocumentWindowController {
    /// The restorable-state key for the picked theme's id (a `String`), absent without a pick.
    static let themeStateKey = "mdvTheme"

    /// The theme the window shows.
    var theme: Theme { coordinator.theme }

    /// The id the window resolves: the reader's pick, else the document's theme, else Settings'
    /// default when the window opened.
    var themeID: String {
        pickedThemeID ?? documentThemeID ?? newWindowThemeID
    }

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

    /// Makes `id` the reader's pick for this window and shows it. Doesn't change the default for
    /// new windows, which only Settings (#36) sets. A pick beats the document's theme.
    func setTheme(id: String) {
        guard id != pickedThemeID else {
            return
        }
        pickedThemeID = id
        applyTheme()
        window?.invalidateRestorableState()
    }

    /// Drops the reader's pick, so the window follows the document's theme (or the default).
    func clearThemePick() {
        guard pickedThemeID != nil else {
            return
        }
        pickedThemeID = nil
        applyTheme()
        window?.invalidateRestorableState()
    }

    /// The document's latest render named `id` as its theme (nil for none). Shows the change in
    /// place unless the reader's pick hides it.
    func documentThemeDidChange(_ id: String?) {
        guard id != documentThemeID else {
            return
        }
        documentThemeID = id
        applyTheme()
    }

    /// Resolves `themeID` in the registry and shows the result: window background, under-page
    /// area, and the page (swapped in place). Does nothing when it is already shown.
    func applyTheme() {
        let theme = themeSettings.theme(forWindowThemeID: themeID)
        window?.backgroundColor = .themeBackground(theme.background)
        coordinator.show(theme)
    }

    // MARK: Actions

    /// View > Theme > <theme>: the sender's `representedObject` is the theme id. Only this window changes; the theme for new windows is Settings' (#36).
    @objc func selectTheme(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String,
            themeSettings.registry.contains(id: id)
        else {
            return
        }
        setTheme(id: id)
    }

    /// View > Theme > Document's Theme: back to the theme the document's frontmatter names.
    @objc func useDocumentTheme(_ sender: Any?) {
        clearThemePick()
    }

    /// Checks the item of the theme the window shows.
    func validateThemeItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = (menuItem.representedObject as? String) == theme.id ? .on : .off
        return true
    }

    /// "Document's Theme": names the document's theme, and is enabled while the reader's pick
    /// hides it. Disabled for a document without one, or while the window already follows it
    /// (the theme's own item is checked then).
    func validateDocumentThemeItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = .off
        guard let documentThemeID else {
            menuItem.title = ThemeMenu.documentThemeTitle
            return false
        }
        let name = themeSettings.theme(forWindowThemeID: documentThemeID).displayName
        menuItem.title = "\(ThemeMenu.documentThemeTitle) (\(name))"
        return pickedThemeID != nil
    }

    // MARK: Restoration

    /// Saves the reader's pick only: a theme that comes from the frontmatter or the default is
    /// worked out again when the window is restored.
    func encodeThemeState(with coder: NSCoder) {
        if let pickedThemeID {
            coder.encode(pickedThemeID as NSString, forKey: Self.themeStateKey)
        }
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
