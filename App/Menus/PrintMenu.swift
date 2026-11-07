import AppKit

/// File > Page Setup… (Command-Shift-P) and Print… (Command-P), handled by `NSDocument`
/// (`runPageLayout(_:)`, `printDocument(_:)`); `MarkdownDocument` supplies the print operation
/// (`DocumentPrinting.swift`).
enum PrintMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [
                NSMenuItem(
                    "Page Setup…", action: #selector(NSDocument.runPageLayout(_:)), key: "p",
                    modifiers: [.command, .shift]),
                NSMenuItem("Print…", action: #selector(NSDocument.printDocument(_:)), key: "p"),
            ], to: .file)
    }
}
