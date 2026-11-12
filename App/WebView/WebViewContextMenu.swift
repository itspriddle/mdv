import AppKit

/// Trims the web view's context menu (#26) to items that work in the viewer. WebKit offers
/// browser items that the navigation policy cancels (Reload, Back, Forward), that need
/// downloads (Download Linked File / Image / Media), or that would open a resource as a page
/// (Open Image / Media / Frame in New Window). Everything else stays: Copy, Copy Link (performed
/// by the app, `redirectCopyLink`), Copy Image (the app's for local images), Open Link and Open Link in New Window (both
/// routed through the link policy), Look Up, Translate, Search With, Share (the app's for local
/// links and images, `replaceShare`), Speech, Services, Writing Tools.
///
/// A blocklist rather than an allowlist, so system items added in later macOS releases keep
/// working. WebKit's identifiers are `WKMenuItemIdentifier…` strings (SPI constants; values
/// confirmed in the WebKit binary).
enum WebViewContextMenu {
    static let removedIdentifiers: Set<String> = [
        "WKMenuItemIdentifierReload",
        "WKMenuItemIdentifierGoBack",
        "WKMenuItemIdentifierGoForward",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierDownloadImage",
        "WKMenuItemIdentifierDownloadMedia",
        "WKMenuItemIdentifierOpenImageInNewWindow",
        "WKMenuItemIdentifierOpenMediaInNewWindow",
        "WKMenuItemIdentifierOpenFrameInNewWindow",
        // Copies the internal `peep-doc` page URL with a text fragment, and Quick Note highlights
        // link back to it; neither means anything outside this window.
        "WKMenuItemIdentifierCopyLinkWithHighlight",
        "WKMenuItemIdentifierAddHighlightToCurrentQuickNote",
        "WKMenuItemIdentifierAddHighlightToNewQuickNote",
    ]

    /// WebKit's Copy Link item, which copies the link's resolved URL: the internal `peep-doc` URL
    /// for a relative link.
    static let copyLinkIdentifier = "WKMenuItemIdentifierCopyLink"

    /// WebKit's Share submenu item, which shares the link's or image's resolved URL.
    static let shareIdentifier = "WKMenuItemIdentifierShareMenu"

    /// Replaces Share with one that shares `items` (the `file:` URLs of a local link or image),
    /// or removes it when `items` is empty. `nil` keeps WebKit's item (nothing local to share).
    @MainActor
    static func replaceShare(in menu: NSMenu, sharing items: [URL]?) {
        guard let items else {
            return
        }
        for item in menu.items where item.identifier?.rawValue == shareIdentifier {
            let index = menu.index(of: item)
            menu.removeItem(item)
            guard !items.isEmpty else {
                continue
            }
            let share = NSSharingServicePicker(items: items).standardShareMenuItem
            share.identifier = item.identifier
            menu.insertItem(share, at: index)
        }
    }

    /// Makes Copy Link perform `target` (`MenuItemTarget.performAction(_:)`) instead of WebKit's
    /// action, or removes it when `target` is nil, so it never copies a `peep-doc` URL (#42).
    @MainActor
    static func redirectCopyLink(in menu: NSMenu, to target: MenuItemTarget?) {
        redirect(copyLinkIdentifier, in: menu, to: target)
    }

    /// WebKit's Copy Image item.
    static let copyImageIdentifier = "WKMenuItemIdentifierCopyImage"

    /// Makes the item `identifier` perform `target` (`MenuItemTarget.performAction(_:)`) instead
    /// of WebKit's action, or removes it when `target` is nil.
    @MainActor
    static func redirect(_ identifier: String, in menu: NSMenu, to target: MenuItemTarget?) {
        for item in menu.items where item.identifier?.rawValue == identifier {
            if let target {
                item.target = target
                item.action = #selector(MenuItemTarget.performAction(_:))
            } else {
                menu.removeItem(item)
            }
        }
    }

    /// Removes the unsupported items from `menu`, then separators left leading, trailing, or
    /// doubled.
    @MainActor
    static func trim(_ menu: NSMenu) {
        for item in menu.items where item.identifier.map({ removedIdentifiers.contains($0.rawValue) }) ?? false {
            menu.removeItem(item)
        }
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator {
                menu.removeItem(item)
            } else {
                previousWasSeparator = item.isSeparatorItem
            }
        }
        if let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }
}

/// A menu item target that runs a closure, for items whose action the app takes over.
@MainActor
final class MenuItemTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func performAction(_ sender: Any?) {
        handler()
    }
}
