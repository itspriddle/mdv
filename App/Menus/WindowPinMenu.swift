import AppKit

/// Window > Pin Window (Option-Command-P). The action is
/// `DocumentWindowController.togglePinned(_:)`, which also retitles the item.
enum WindowPinMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [
                NSMenuItem(
                    "Pin Window", action: #selector(DocumentWindowController.togglePinned(_:)), key: "p",
                    modifiers: [.command, .option])
            ], to: .window)
    }
}
