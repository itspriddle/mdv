import AppKit

/// Edit > Find: the standard find commands (`performTextFinderAction(_:)`, tagged with
/// `NSTextFinder.Action`), handled by `DocumentWindowController+Find.swift`.
enum FindMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        let find = NSMenu(title: "Find")
        for item in [
            item("Find…", .showFindInterface, key: "f"),
            item("Find Next", .nextMatch, key: "g"),
            item("Find Previous", .previousMatch, key: "g", modifiers: [.command, .shift]),
            item("Use Selection for Find", .setSearchString, key: "e"),
        ] {
            find.addItem(item)
        }
        menu.addGroup([NSMenuItem("Find", submenu: find)], to: .edit)
    }

    private static func item(
        _ title: String, _ action: NSTextFinder.Action, key: String, modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title, action: #selector(NSResponder.performTextFinderAction(_:)), key: key, modifiers: modifiers)
        item.tag = action.rawValue
        return item
    }
}
