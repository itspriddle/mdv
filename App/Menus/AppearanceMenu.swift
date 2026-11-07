import AppKit

/// View > Appearance: System, Light, and Dark, the current one checked (the same setting as
/// Settings > Appearance). The action is `AppDelegate.chooseAppearance(_:)`, so the items work
/// without a document window.
enum AppearanceMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        let submenu = NSMenu(title: "Appearance")
        for mode in AppearanceMode.allCases {
            let item = NSMenuItem(mode.displayName, action: #selector(AppDelegate.chooseAppearance(_:)))
            item.representedObject = mode.rawValue
            submenu.addItem(item)
            if mode == .system {
                submenu.addItem(.separator())
            }
        }
        menu.addGroup([NSMenuItem("Appearance", submenu: submenu)], to: .view)
    }
}
