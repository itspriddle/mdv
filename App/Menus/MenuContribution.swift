import AppKit

/// A feature's items in the main menu.
///
/// Each feature that needs menu items adds one type conforming to this protocol in its own file
/// in `App/Menus/` (e.g. `ZoomMenu.swift`) and one line to `MainMenu.contributions`. Items use a
/// nil target, so the action travels the responder chain: the web view, the window,
/// `DocumentWindowController` (implement actions in `DocumentWindowController+<Feature>.swift`),
/// then `MarkdownDocument`. A responder that implements the action enables the item; implement
/// `NSMenuItemValidation` on that responder only when the item also needs state.
@MainActor
protocol MenuContribution {
    /// Adds this feature's item groups with `MainMenu.addGroup(_:to:)`.
    static func contribute(to menu: MainMenu)
}

extension NSMenuItem {
    /// A menu item that sends `action` up the responder chain.
    convenience init(
        _ title: String, action: Selector?, key: String = "", modifiers: NSEvent.ModifierFlags = .command
    ) {
        self.init(title: title, action: action, keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
    }

    /// A submenu item.
    convenience init(_ title: String, submenu: NSMenu) {
        self.init(title: title, action: nil, keyEquivalent: "")
        self.submenu = submenu
    }
}
