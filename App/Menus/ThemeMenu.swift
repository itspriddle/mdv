import AppKit
import MdvCore

/// View > Theme (#34): one item per registered theme, bundled themes first and added (custom,
/// #35) themes in their own section (`ThemeRegistry.pickerSections`), followed by custom theme
/// files that didn't load (disabled, with the reason). The action is
/// `DocumentWindowController.selectTheme(_:)`; its validation checks the window's theme. The
/// items are rebuilt each time the menu opens, so themes added or removed while the app runs
/// show up. View > Theme ends with "Open Themes Folder" (`AppDelegate.openThemesFolder(_:)`).
enum ThemeMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [NSMenuItem("Theme", submenu: makeMenu(settings: .shared, includesFolderItem: true))], to: .view)
    }

    /// A theme menu listing `settings.registry`, kept current while the app runs.
    static func makeMenu(settings: ThemeSettings, includesFolderItem: Bool = false) -> NSMenu {
        ThemePickerMenu(settings: settings, includesFolderItem: includesFolderItem)
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
    private let includesFolderItem: Bool

    init(settings: ThemeSettings, includesFolderItem: Bool = false) {
        self.settings = settings
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
        if includesFolderItem {
            items += [.separator(), ThemeMenu.folderItem()]
        }
        menu.items = items
    }
}
