import AppKit
import WebKit

/// The document web view. A `WKWebView` that takes over drag and drop: files mdv can open
/// (Markdown, plain text) go to `fileDropHandler`, which opens them as new tabs; every other
/// drag is refused, so WebKit never loads or inserts what is dropped on the page.
@MainActor
final class DocumentWebView: WKWebView {
    /// Opens dropped files (already filtered to documents mdv can open). Set by the window.
    var fileDropHandler: (([URL]) -> Void)?

    /// Performs the context menu's Copy Link in place of WebKit, which would copy the internal
    /// `mdv-doc` URL of a relative link (#42). Set by the coordinator; without it, Copy Link is
    /// removed from the menu.
    var copyLinkHandler: (() -> Void)?

    /// Takes `mdv-doc` URLs off a drag's pasteboard before the drag starts (a dragged link or
    /// image). Set by the coordinator.
    var dragPasteboardHandler: ((NSPasteboard) -> Void)?

    /// What the context menu's Share shares in place of WebKit's item, which would share the
    /// internal `mdv-doc` URL of a relative link or local image: `nil` keeps WebKit's item, an
    /// empty list removes it. Set by the coordinator; without it, Share is removed.
    var shareItemsHandler: (() -> [URL]?)?

    /// Performs Copy Image for a local image in place of WebKit, which copies nothing for an SVG
    /// and writes HTML with the image's `mdv-doc` URL. Used only when
    /// `isLocalImageUnderContextMenu` says so; other images keep WebKit's Copy Image. Set by the
    /// coordinator.
    var copyImageHandler: (() -> Void)?
    var isLocalImageUnderContextMenu: (() -> Bool)?

    private lazy var copyImageTarget = MenuItemTarget { [weak self] in
        self?.copyImageHandler?()
    }

    /// The context menu's Copy Link target (menu item targets are weak).
    private lazy var copyLinkTarget = MenuItemTarget { [weak self] in
        self?.copyLinkHandler?()
    }

    /// What WebKit paints behind and around the page (rubber-band overscroll): a dynamic color,
    /// resolved for this view's appearance. It doesn't cover the view before the first paint;
    /// `hideOpaqueBackground()` does that.
    ///
    /// Use this, not `underPageBackgroundColor`, for a dynamic color. Some WebKit versions
    /// (macOS 26) store that color resolved for the appearance current when it is set, so a dark
    /// mode window would keep a light color (or the reverse) after an appearance change. This
    /// sets it resolved and sets it again whenever the effective appearance changes.
    var themeUnderPageBackgroundColor: NSColor? {
        didSet { applyThemeUnderPageBackgroundColor() }
    }

    /// Stops WebKit from painting its own opaque white background behind the page, so the
    /// window's theme background shows through until the first page paints (the page's CSS then
    /// paints the same color). Returns whether WebKit took the setting.
    ///
    /// There is no public API for this: `drawsBackground` is WebKit SPI, reached through
    /// key-value coding (which finds `_setDrawsBackground:`). The check keeps a WebKit without it
    /// from raising; the web view then only flashes white before the first paint, as before.
    @discardableResult
    func hideOpaqueBackground() -> Bool {
        guard responds(to: NSSelectorFromString("_setDrawsBackground:")) else {
            return false
        }
        setValue(false, forKey: "drawsBackground")
        return !isOpaque
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyThemeUnderPageBackgroundColor()
    }

    private func applyThemeUnderPageBackgroundColor() {
        guard let color = themeUnderPageBackgroundColor else {
            return
        }
        var resolved: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        underPageBackgroundColor = resolved ?? color
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropOperation(for: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropOperation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {}

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !openableFiles(in: sender).isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let files = openableFiles(in: sender)
        guard !files.isEmpty, let fileDropHandler else {
            return false
        }
        fileDropHandler(files)
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {}

    override func draggingEnded(_ sender: any NSDraggingInfo) {}

    /// The context menu, without the items the viewer can't perform (`WebViewContextMenu`, #26).
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        WebViewContextMenu.redirectCopyLink(in: menu, to: copyLinkHandler == nil ? nil : copyLinkTarget)
        if isLocalImageUnderContextMenu?() == true {
            WebViewContextMenu.redirect(
                WebViewContextMenu.copyImageIdentifier, in: menu, to: copyImageHandler == nil ? nil : copyImageTarget)
        }
        WebViewContextMenu.replaceShare(in: menu, sharing: shareItemsHandler.map { $0() } ?? [])
        WebViewContextMenu.trim(menu)
    }

    /// Jump to Selection goes to the window controller, which knows the current find match.
    /// WebKit's own command would scroll only the page's selection.
    override func responds(to selector: Selector?) -> Bool {
        if selector == #selector(NSResponder.centerSelectionInVisibleArea(_:)) {
            return false
        }
        return super.responds(to: selector)
    }

    /// Pinch-to-zoom changes the window's magnification, which window restoration keeps.
    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        window?.invalidateRestorableState()
    }

    override func smartMagnify(with event: NSEvent) {
        super.smartMagnify(with: event)
        window?.invalidateRestorableState()
    }

    // MARK: Dragging out

    /// The drag source callback AppKit sends when any drag from the page starts, after WebKit
    /// has written the pasteboard and before anything can be dropped: the rewrite goes here.
    /// `WKWebView` implements it without declaring it (WebKit starts link and image drags with
    /// `dragImage(…)`, which Swift can't override), so this replaces it by selector and then
    /// calls WebKit's implementation.
    @objc(draggingSession:willBeginAtPoint:)
    func documentDraggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        dragPasteboardHandler?(session.draggingPasteboard)
        let selector = #selector(documentDraggingSession(_:willBeginAt:))
        guard WKWebView.instancesRespond(to: selector),
            let implementation = class_getMethodImplementation(WKWebView.self, selector)
        else {
            return
        }
        typealias WillBegin = @convention(c) (AnyObject, Selector, NSDraggingSession, NSPoint) -> Void
        unsafeBitCast(implementation, to: WillBegin.self)(self, selector, session, screenPoint)
    }

    private func dropOperation(for sender: any NSDraggingInfo) -> NSDragOperation {
        fileDropHandler != nil && !openableFiles(in: sender).isEmpty ? .copy : []
    }

    private func openableFiles(in sender: any NSDraggingInfo) -> [URL] {
        DocumentDrop.openableFiles(on: sender.draggingPasteboard)
    }
}

/// Which dropped files mdv opens.
@MainActor
enum DocumentDrop {
    /// The file URLs on `pasteboard` that `controller` has a document class for (Markdown and
    /// plain text, per the app's declared document types, and extensionless text files, per
    /// `DocumentController.typeForContents(of:)`), in order. Folders and other files are left
    /// out.
    static func openableFiles(
        on pasteboard: NSPasteboard, controller: NSDocumentController = .shared
    ) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let urls = (objects ?? []).compactMap { $0 as? URL }
        return urls.filter { url in
            guard let type = try? controller.typeForContents(of: url) else {
                return false
            }
            return controller.documentClass(forType: type) != nil
        }
    }
}
