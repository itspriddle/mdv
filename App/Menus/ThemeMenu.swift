import AppKit
import MdvCore

/// View > Theme (#34): one item per registered theme, bundled themes first and added (custom,
/// #35) themes in their own section (`ThemeRegistry.pickerSections`). The action is
/// `DocumentWindowController.selectTheme(_:)`; its validation checks the window's theme. The
/// items are rebuilt each time the menu opens, so themes added or removed while the app runs
/// show up. The toolbar's theme menu is the same menu (`makeMenu(settings:)`).
enum ThemeMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup([NSMenuItem("Theme", submenu: makeMenu(settings: .shared))], to: .view)
    }

    /// A theme menu listing `settings.registry`, kept current while the app runs.
    static func makeMenu(settings: ThemeSettings) -> NSMenu {
        ThemePickerMenu(settings: settings)
    }

    /// The items for `registry`: one per theme, sections separated.
    static func items(for registry: ThemeRegistry) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for (index, section) in registry.pickerSections().enumerated() {
            if index > 0 {
                items.append(.separator())
            }
            for theme in section {
                let item = NSMenuItem(
                    theme.displayName, action: #selector(DocumentWindowController.selectTheme(_:)))
                item.representedObject = theme.id
                items.append(item)
            }
        }
        return items
    }
}

/// A theme menu that rebuilds its items from the current registry before it opens. It owns its
/// delegate (`NSMenu.delegate` is weak).
@MainActor
final class ThemePickerMenu: NSMenu, NSMenuDelegate {
    private let settings: ThemeSettings

    init(settings: ThemeSettings) {
        self.settings = settings
        super.init(title: "Theme")
        delegate = self
        menuNeedsUpdate(self)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("ThemePickerMenu is created in code")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items = ThemeMenu.items(for: settings.registry)
    }
}
