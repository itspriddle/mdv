import AppKit
import PeepCore

/// The window's theme (#34, #54): View > Theme picks it, the switch is in place
/// (`WebViewCoordinator.show(_:)`, no reload), and window restoration keeps the pick.
///
/// Precedence, highest first (`themeID`):
/// 1. the reader's pick for this window (`pickedThemeID`, View > Theme);
/// 2. the document's frontmatter theme (`documentThemeID`, `peep.theme`, #54);
/// 3. Settings' default when the window opened (`newWindowThemeID`).
///
/// The window shows `themeSettings.theme(forWindowThemeID: themeID)`: an unknown or removed id
/// (a deleted or broken custom theme, #35, or a frontmatter id that isn't registered) falls back
/// to Settings' default theme (#45), and a custom theme whose CSS changed is swapped in when the
/// registry is replaced. The ids are kept, so the theme comes back when its file does.
/// Restoration saves only the pick, so a frontmatter theme edited while the app was closed takes
/// effect on relaunch. A live reload that changes `peep.theme` swaps the theme in place.
extension DocumentWindowController {
    /// The restorable-state key for the picked theme's id (a `String`), absent without a pick.
    static let themeStateKey = "peepTheme"

    /// The theme the window shows.
    var theme: Theme { coordinator.theme }

    /// The id the window resolves: the reader's pick, else the document's theme, else Settings'
    /// default when the window opened.
    var themeID: String {
        pickedThemeID ?? documentThemeID ?? newWindowThemeID
    }

    /// Applies the window's theme and follows registry changes. Called once from `init`.
    func installTheme() {
        // The titlebar shows the window background (the theme's), with the page's border under it
        // (`DocumentView`) instead of the system separator.
        window?.titlebarAppearsTransparent = true
        window?.titlebarSeparatorStyle = .none
        appAppearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.applyWindowChrome()
            }
        }
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
        chrome.background = theme.background
        renderProgress.background = theme.background
        applyWindowChrome()
        coordinator.show(theme)
    }

    /// Paints the titlebar and outline sidebar with the theme's background in the system
    /// appearance (the sidebar's edge in its border color), and keeps the
    /// titlebar's title and buttons legible on it.
    ///
    /// When the background's darkness matches the appearance (always, for the bundled themes), the
    /// window keeps the appearance it had and its background follows appearance changes by
    /// itself. When it doesn't (a custom theme with one dark background, in Light mode), the
    /// window's appearance is forced to the background's, the content view is pinned to the
    /// system's (so the page's `prefers-color-scheme`, the outline, and the bars still follow
    /// it), and the background is the one color. The window's earlier appearance is restored
    /// once they match again.
    func applyWindowChrome() {
        guard let window else {
            return
        }
        let system =
            forcedAppearance.map { $0.previous ?? NSApplication.shared.effectiveAppearance }
            ?? window.effectiveAppearance
        let systemIsDark = system.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let background = systemIsDark ? chrome.background.dark : chrome.background.light
        if background.isDark == systemIsDark {
            if let forcedAppearance {
                window.appearance = forcedAppearance.previous
                self.forcedAppearance = nil
            }
            window.contentView?.appearance = nil
            outlineController.view.appearance = nil
            window.backgroundColor = .themeBackground(chrome.background)
            outlineController.chromeView.backgroundColor = .themeBackground(chrome.background)
            outlineController.chromeView.borderColor = .themeBorder(chrome.background)
        } else {
            if forcedAppearance == nil {
                forcedAppearance = ForcedWindowAppearance(previous: window.appearance)
            }
            window.appearance = NSAppearance(named: background.isDark ? .darkAqua : .aqua)
            window.contentView?.appearance = NSAppearance(named: systemIsDark ? .darkAqua : .aqua)
            window.backgroundColor = NSColor(background)
            // The sidebar is chrome too: drawn in the background's appearance, like the titlebar.
            outlineController.view.appearance = window.appearance
            outlineController.chromeView.backgroundColor = NSColor(background)
            outlineController.chromeView.borderColor = NSColor(background.chromeBorder)
        }
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

/// A window appearance `applyWindowChrome()` replaced, to put back once it no longer forces one.
struct ForcedWindowAppearance {
    let previous: NSAppearance?
}
