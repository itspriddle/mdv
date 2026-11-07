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

    /// The context menu's Copy Link target (menu item targets are weak).
    private lazy var copyLinkTarget = MenuItemTarget { [weak self] in
        self?.copyLinkHandler?()
    }

    /// What WebKit paints behind and around the page (rubber-band overscroll, and before the
    /// first paint): a dynamic color, resolved for this view's appearance.
    ///
    /// Use this, not `underPageBackgroundColor`, for a dynamic color. Some WebKit versions
    /// (macOS 26) store that color resolved for the appearance current when it is set, so a dark
    /// mode window would keep a light color (or the reverse) after an appearance change. This
    /// sets it resolved and sets it again whenever the effective appearance changes.
    var themeUnderPageBackgroundColor: NSColor? {
        didSet { applyThemeUnderPageBackgroundColor() }
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
    /// plain text, per the app's declared document types), in order. Folders and other files
    /// are left out.
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
