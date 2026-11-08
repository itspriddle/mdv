import AppKit
import MdvCore

/// View > Theme (#34): one item per registered theme, bundled themes first and added (custom,
/// #35) themes in their own section (`ThemeRegistry.pickerSections`), followed by custom theme
/// files that didn't load (disabled, with the reason). The action is
/// `DocumentWindowController.selectTheme(_:)`; its validation checks the window's theme. The
/// items are rebuilt each time the menu opens, so themes added or removed while the app runs
/// show up. View > Theme starts with "Document's Theme" (#54,
/// `DocumentWindowController.useDocumentTheme(_:)`), which drops the window's pick so the
/// frontmatter's `mdv.theme` shows again, and ends with "Open Themes Folder"
/// (`AppDelegate.openThemesFolder(_:)`).
enum ThemeMenu: MenuContribution {
    /// The "Document's Theme" item's title; validation adds the theme's name.
    static let documentThemeTitle = "Document's Theme"

    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [
                NSMenuItem(
                    "Theme",
                    submenu: makeMenu(settings: .shared, includesDocumentThemeItem: true, includesFolderItem: true))
            ], to: .view)
    }

    /// A theme menu listing `settings.registry`, kept current while the app runs.
    static func makeMenu(
        settings: ThemeSettings, includesDocumentThemeItem: Bool = false, includesFolderItem: Bool = false
    ) -> NSMenu {
        ThemePickerMenu(
            settings: settings, includesDocumentThemeItem: includesDocumentThemeItem,
            includesFolderItem: includesFolderItem)
    }

    /// View > Theme > Document's Theme (#54).
    static func documentThemeItem() -> NSMenuItem {
        NSMenuItem(documentThemeTitle, action: #selector(DocumentWindowController.useDocumentTheme(_:)))
    }

    /// The items for `registry`: one per theme, sections separated, then one disabled item per
    /// failure in the custom section.
    static func items(for registry: ThemeRegistry, failures: [CustomThemeFailure] = []) -> [NSMenuItem] {
        var sections = registry.pickerSections().map { section in
            section.map { theme in
                let item = NSMenuItem(theme.displayName, action: #selector(DocumentWindowController.selectTheme(_:)))
                item.representedObject = theme.id
                return item
            }
        }
        let failed = failures.map(failureItem)
        if !failed.isEmpty {
            if sections.count > 1 {
                sections[sections.count - 1] += failed
            } else {
                sections.append(failed)
            }
        }
        var items: [NSMenuItem] = []
        for (index, section) in sections.enumerated() {
            if index > 0 {
                items.append(.separator())
            }
            items += section
        }
        return items
    }

    /// A disabled item (no action) naming a theme file that didn't load and why.
    static func failureItem(_ failure: CustomThemeFailure) -> NSMenuItem {
        let item = NSMenuItem(title: failure.message, action: nil, keyEquivalent: "")
        item.toolTip = failure.message
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Not loaded")
        item.isEnabled = false
        return item
    }

    /// View > Theme > Open Themes Folder.
    static func folderItem() -> NSMenuItem {
        NSMenuItem("Open Themes Folder", action: #selector(AppDelegate.openThemesFolder(_:)))
    }
}

/// A theme menu that rebuilds its items from the current registry before it opens. It owns its
/// delegate (`NSMenu.delegate` is weak).
@MainActor
final class ThemePickerMenu: NSMenu, NSMenuDelegate {
    private let settings: ThemeSettings
    private let includesDocumentThemeItem: Bool
    private let includesFolderItem: Bool

    init(settings: ThemeSettings, includesDocumentThemeItem: Bool = false, includesFolderItem: Bool = false) {
        self.settings = settings
        self.includesDocumentThemeItem = includesDocumentThemeItem
        self.includesFolderItem = includesFolderItem
        super.init(title: "Theme")
        delegate = self
        menuNeedsUpdate(self)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("ThemePickerMenu is created in code")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        var items = ThemeMenu.items(for: settings.registry, failures: settings.customThemeFailures)
        if includesDocumentThemeItem {
            items = [ThemeMenu.documentThemeItem(), .separator()] + items
        }
        if includesFolderItem {
            items += [.separator(), ThemeMenu.folderItem()]
        }
        menu.items = items
    }
}
