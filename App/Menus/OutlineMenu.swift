import AppKit

/// View > Show/Hide Outline (Command-Control-S, the standard sidebar shortcut). The action is
/// `DocumentWindowController.toggleOutline(_:)`, which also retitles the item.
enum OutlineMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [
                NSMenuItem(
                    "Show Outline", action: #selector(DocumentWindowController.toggleOutline(_:)), key: "s",
                    modifiers: [.command, .control])
            ], to: .view)
    }
}
