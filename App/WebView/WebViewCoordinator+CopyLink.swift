import AppKit
import MdvCore

/// The context menu's Copy Link (#42). WebKit would copy a relative link's resolved URL, the
/// window's internal `mdv-doc` URL; this copies what `CopyableLink` picks instead: the `file:`
/// URL it names, or an external URL as is. `App/Scripts/ContextMenuLink.js` records the link
/// the menu was opened on.
extension WebViewCoordinator {
    /// Longest href copied; longer ones are refused. Bounds the work a hostile document can cause.
    static let maximumCopiedLinkLength = 64 * 1024

    /// Copies the context menu's link to the general pasteboard; beeps when there is nothing to
    /// copy.
    func copyContextMenuLink() {
        Task {
            if await !copyContextMenuLink(to: .general) {
                NSSound.beep()
            }
        }
    }

    /// Copies the link the context menu was last opened on to `pasteboard`. Returns `false`, and
    /// leaves the pasteboard alone, when there is no link or it names nothing copyable.
    func copyContextMenuLink(to pasteboard: NSPasteboard) async -> Bool {
        guard let href = try? await callBridge("return mdvContextMenu.link();") as? String,
            !href.isEmpty, href.utf8.count <= Self.maximumCopiedLinkLength,
            let url = URL(string: href),
            let link = CopyableLink.url(for: url, token: localResources.token)
        else {
            return false
        }
        DocumentPasteboard.writeLink(link, to: pasteboard)
        return true
    }
}
