import AppKit

/// View > Show/Hide Status Bar (Command-/, as in Safari and Finder). The action is
/// `DocumentWindowController.toggleStatusBar(_:)`, which also retitles the item.
enum StatusBarMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [NSMenuItem("Show Status Bar", action: #selector(DocumentWindowController.toggleStatusBar(_:)), key: "/")],
            to: .view)
    }
}
