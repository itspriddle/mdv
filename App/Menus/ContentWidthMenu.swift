import AppKit
import PeepCore

/// View > Content Width: a submenu with one item per `ContentWidth` preset, the current one
/// checked, then (after a separator) Settings' custom width, shown only while it is on
/// (`validateContentWidthItem`). The action is `DocumentWindowController.setContentWidth(_:)` (`+ContentWidth.swift`),
/// so the items are disabled without a document window.
enum ContentWidthMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        let submenu = NSMenu(title: "Content Width")
        for width in ContentWidth.allCases {
            let item = NSMenuItem(width.displayName, action: #selector(DocumentWindowController.setContentWidth(_:)))
            item.representedObject = width.rawValue
            submenu.addItem(item)
        }
        let separator = NSMenuItem.separator()
        separator.isHidden = true
        submenu.addItem(separator)
        let custom = NSMenuItem("Custom", action: #selector(DocumentWindowController.setContentWidth(_:)))
        custom.representedObject = DocumentWindowController.customContentWidthItemValue
        custom.isHidden = true
        submenu.addItem(custom)
        menu.addGroup([NSMenuItem("Content Width", submenu: submenu)], to: .view)
    }
}
