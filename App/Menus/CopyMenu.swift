import AppKit

/// Edit > Copy Markdown Source and Copy as HTML. No shortcuts: there is no standard one, and
/// Command-Option-C is Copy Style in text apps. Actions are on `DocumentWindowController`
/// (`+Copy.swift`), so they're disabled without a document window.
enum CopyMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [
                NSMenuItem(
                    "Copy Markdown Source", action: #selector(DocumentWindowController.copyMarkdownSource(_:))),
                NSMenuItem("Copy as HTML", action: #selector(DocumentWindowController.copyAsHTML(_:))),
            ], to: .edit)
    }
}
