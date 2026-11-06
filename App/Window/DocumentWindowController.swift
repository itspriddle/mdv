import AppKit
import SwiftUI

/// One document window: an AppKit window hosting `DocumentView` (SwiftUI), with a
/// `WebViewCoordinator` for the page.
///
/// The controller is in the responder chain (window, then controller, then document), so menu
/// items with a nil target reach it. Features add their menu actions as `@objc` methods in an
/// extension file, `DocumentWindowController+<Feature>.swift`.
@MainActor
final class DocumentWindowController: NSWindowController {
    let coordinator: WebViewCoordinator

    /// The document this window shows, once `NSDocument.addWindowController` has set it.
    var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    private var displayTask: Task<Void, Never>?
    /// A fragment to scroll to once the page loads (a link opened this document with `#…`).
    var pendingFragment: String?

    init(coordinator: WebViewCoordinator = WebViewCoordinator()) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.backgroundColor = .themeBackground
        window.minSize = NSSize(width: 480, height: 360)
        window.center()
        super.init(window: window)
        installLinkHandling()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DocumentWindowController is created in code")
    }

    override var document: AnyObject? {
        didSet {
            guard let markdownDocument, window?.contentViewController == nil else {
                return
            }
            let hostingController = NSHostingController(
                rootView: DocumentView(document: markdownDocument, coordinator: coordinator))
            // SwiftUI sets the minimum size; the window (and later restoration) owns the size.
            hostingController.sizingOptions = [.minSize]
            hostingController.view.frame.size = window?.contentLayoutRect.size ?? .zero
            window?.contentViewController = hostingController
            documentContentDidChange()
        }
    }

    /// Called by `MarkdownDocument.setContent(_:)` after every (re)load, and once when the
    /// window is attached to its document.
    ///
    /// TODO(#21): preserve the reading position across reloads (`currentSourceLine()` before,
    /// `scroll(toSourceLine:)` after, or `replaceContent(with:baseURL:)`).
    func documentContentDidChange() {
        guard let markdownDocument, let page = markdownDocument.content?.page else {
            return
        }
        synchronizeWindowTitleWithDocumentName()
        coordinator.documentFileURL = markdownDocument.fileURL
        let baseURL = markdownDocument.fileURL?.deletingLastPathComponent()
        let isFirstLoad = !coordinator.hasLoadedPage
        displayTask?.cancel()
        displayTask = Task { [coordinator, weak self] in
            do {
                try await coordinator.load(page, baseURL: baseURL)
                await self?.scrollToPendingFragment()
                if isFirstLoad {
                    // Arrow keys, space, and Page Down scroll the document right away.
                    self?.window?.makeFirstResponder(coordinator.webView)
                }
            } catch {
                // A newer load cancels this one; nothing else to show.
            }
        }
    }

    /// The window title is the document's title (frontmatter `title`, then the first `h1`),
    /// falling back to the file name.
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        markdownDocument?.content?.page.title ?? displayName
    }
}
