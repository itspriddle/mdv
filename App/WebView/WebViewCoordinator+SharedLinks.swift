import AppKit
import MdvCore
import WebKit

/// Keeps the window's internal `mdv-doc` URLs out of what leaves the page by WebKit's own
/// routes, as Copy Link does (#42): a dragged link or image carries the `file:` URL it names
/// (`PasteboardLinkRewriter`), Share on a local link or image shares that `file:` URL, and Copy
/// Image on a local image is the app's.
extension WebViewCoordinator {
    /// Copy Image draws at most this many pixels a side.
    static let maximumCopiedImageSide = 8192

    /// The `mdv-doc` URL of the image under the last context menu, if it is a local image.
    var contextMenuLocalImage: URL? {
        guard let image = contextMenuTarget.image, image.scheme?.lowercased() == DocumentURLScheme.name else {
            return nil
        }
        return image
    }

    /// Copies the context menu's local image to the general pasteboard; beeps when there is
    /// nothing to copy.
    func copyContextMenuImage() {
        Task {
            if await !copyContextMenuImage(to: .general) {
                NSSound.beep()
            }
        }
    }

    /// Copies the local image the context menu was last opened on to `pasteboard`
    /// (`DocumentPasteboard.writeImage`): the file as `LocalImagePolicy` serves it to the page,
    /// read again, and a PNG the page draws, so nothing is decoded in the app. Returns `false`,
    /// and leaves the pasteboard alone, when there is neither.
    func copyContextMenuImage(to pasteboard: NSPasteboard) async -> Bool {
        guard let url = contextMenuLocalImage else {
            return false
        }
        let policy = localResources.policy
        let original = await Task.detached(priority: .userInitiated) { policy?.image(for: url) }.value
        let drawn =
            try? await callBridge(
                "return mdvContextMenu.imagePNG(maximumSide);", arguments: ["maximumSide": Self.maximumCopiedImageSide])
        let png = (drawn as? String).flatMap(Self.pngData(fromDataURL:))
        guard original != nil || png != nil else {
            return false
        }
        DocumentPasteboard.writeImage(original: original, png: png, to: pasteboard)
        return true
    }

    /// The PNG in a `data:image/png;base64,` URL from `imagePNG`; nil for anything else.
    nonisolated static func pngData(fromDataURL string: String) -> Data? {
        let prefix = "data:image/png;base64,"
        guard string.hasPrefix(prefix),
            let data = Data(base64Encoded: String(string.dropFirst(prefix.count))),
            ImageFormat.sniff(data) == .png
        else {
            return nil
        }
        return data
    }

    /// Rewrites the `mdv-doc` URLs on a drag's `pasteboard` (see `PasteboardLinkRewriter`).
    /// Leaves it alone when there are none.
    ///
    /// Changed types are written over in place, and dropped ones emptied: declaring the types
    /// again would end WebKit's ownership of the pasteboard, and WebKit then discards the image
    /// file it promised, so dropping an image in Finder would create nothing.
    func rewriteDocumentLinks(on pasteboard: NSPasteboard) {
        let entries = (pasteboard.types ?? []).compactMap { type in
            pasteboard.data(forType: type).map { PasteboardLinkRewriter.Entry(type: type.rawValue, data: $0) }
        }
        guard let rewritten = PasteboardLinkRewriter.rewrite(entries, token: localResources.token) else {
            return
        }
        let kept = Dictionary(rewritten.map { ($0.type, $0.data) }, uniquingKeysWith: { first, _ in first })
        for entry in entries {
            let data = kept[entry.type] ?? Data()
            if data != entry.data {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(entry.type))
            }
        }
    }

    /// What Share shares for the last context menu (`WebViewContextMenu.replaceShare`): `nil`
    /// (WebKit's own Share) unless the link or image under it has an `mdv-doc` URL; then the
    /// `file:` URLs they name, or nothing when they name no file.
    func contextMenuShareItems() -> [URL]? {
        let urls = [contextMenuTarget.link, contextMenuTarget.image].compactMap { $0 }
        guard urls.contains(where: { $0.scheme?.lowercased() == DocumentURLScheme.name }) else {
            return nil
        }
        return urls.compactMap { CopyableLink.url(for: $0, token: localResources.token) }
    }
}

/// The link and image a context menu was opened on, as resolved URLs.
struct ContextMenuTarget: Equatable {
    var link: URL?
    var image: URL?
}

/// Receives `ContextMenuLink.js` reports of what the context menu was opened on. Registered in
/// `AppScripts.world` only, so the page can't post to it; the URLs still come from the document,
/// so they are length-checked and only ever mapped through `CopyableLink`. Holds its
/// coordinator weakly (the user content controller retains its handlers).
@MainActor
final class ContextMenuTargetMessageHandler: NSObject, WKScriptMessageHandler {
    /// The message handler name `ContextMenuLink.js` posts to.
    static let name = "contextMenuTarget"

    weak var coordinator: WebViewCoordinator?

    init(coordinator: WebViewCoordinator) {
        self.coordinator = coordinator
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame, message.world.name == AppScripts.world.name, let coordinator else {
            return
        }
        let body = message.body as? [String: Any]
        coordinator.contextMenuTarget = ContextMenuTarget(
            link: Self.url(body?["link"]), image: Self.url(body?["image"]))
    }

    /// A non-empty string of at most `WebViewCoordinator.maximumCopiedLinkLength` UTF-8 bytes
    /// that parses as a URL.
    static func url(_ value: Any?) -> URL? {
        guard let string = value as? String, !string.isEmpty,
            string.utf8.count <= WebViewCoordinator.maximumCopiedLinkLength
        else {
            return nil
        }
        return URL(string: string)
    }
}
