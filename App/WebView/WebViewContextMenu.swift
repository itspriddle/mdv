import AppKit

/// Trims the web view's context menu (#26) to items that work in the viewer. WebKit offers
/// browser items that the navigation policy cancels (Reload, Back, Forward), that need
/// downloads (Download Linked File / Image / Media), or that would open a resource as a page
/// (Open Image / Media / Frame in New Window). Everything else stays: Copy, Copy Link, Copy
/// Image, Open Link and Open Link in New Window (both routed through the link policy), Look
/// Up, Translate, Search With, Share, Speech, Services, Writing Tools.
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
        // Copies the internal `mdv-doc` page URL with a text fragment, and Quick Note highlights
        // link back to it; neither means anything outside this window.
        "WKMenuItemIdentifierCopyLinkWithHighlight",
        "WKMenuItemIdentifierAddHighlightToCurrentQuickNote",
        "WKMenuItemIdentifierAddHighlightToNewQuickNote",
    ]

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
