import AppKit

/// View > Show/Hide Outline (Command-Control-S, the standard sidebar shortcut). The action is
/// `DocumentWindowController.toggleOutline(_:)`, which also retitles the item. Expand All
/// Headings and Collapse All Headings act on the visible outline (#43).
enum OutlineMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [
                NSMenuItem(
                    "Show Outline", action: #selector(DocumentWindowController.toggleOutline(_:)), key: "s",
                    modifiers: [.command, .control]),
                NSMenuItem(
                    "Expand All Headings", action: #selector(DocumentWindowController.expandAllOutlineEntries(_:))),
                NSMenuItem(
                    "Collapse All Headings",
                    action: #selector(DocumentWindowController.collapseAllOutlineEntries(_:))),
            ], to: .view)
    }
}
