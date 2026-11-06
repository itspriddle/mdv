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
    /// The base URL of the loaded page; content swaps in place only while it is unchanged.
    private var loadedBaseURL: URL?
    private var hasShownPage = false
    private var canRecoverFromCrash = true

    init(coordinator: WebViewCoordinator = WebViewCoordinator()) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.backgroundColor = .themeBackground
        window.minSize = NSSize(width: 480, height: 360)
        window.center()
        super.init(window: window)
        coordinator.webContentProcessDidTerminate = { [weak self] in
            self?.webContentProcessDidTerminate()
        }
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
    /// Live reload keeps the reading position: content is swapped into the loaded page in place
    /// (`updateContent(with:baseURL:)`), with no reload and no flash. Only when the base URL
    /// changed (the file moved) is the page loaded again, and the position restored after.
    func documentContentDidChange() {
        canRecoverFromCrash = true
        display()
    }

    /// Shows the document's current content. Display tasks run one at a time, in order; a task
    /// that a newer one superseded before it started is skipped.
    private func display() {
        guard let markdownDocument, let page = markdownDocument.content?.page else {
            return
        }
        synchronizeWindowTitleWithDocumentName()
        let baseURL = markdownDocument.fileURL?.deletingLastPathComponent()
        let previous = displayTask
        previous?.cancel()
        displayTask = Task { [coordinator, weak self] in
            await previous?.value
            guard !Task.isCancelled, let self else {
                return
            }
            do {
                if coordinator.hasLoadedPage, baseURL == loadedBaseURL {
                    try await coordinator.updateContent(with: page, baseURL: baseURL)
                } else if coordinator.hasLoadedPage {
                    let position = try? await coordinator.readingPosition()
                    try await coordinator.load(page, baseURL: baseURL)
                    if let position {
                        try await coordinator.restore(position)
                    }
                } else {
                    try await coordinator.load(page, baseURL: baseURL)
                }
                loadedBaseURL = baseURL
                if !hasShownPage {
                    hasShownPage = true
                    // Arrow keys, space, and Page Down scroll the document right away.
                    window?.makeFirstResponder(coordinator.webView)
                }
            } catch {
                // A newer load cancelled this one, or the web content process exited (handled
                // by `webContentProcessDidTerminate()`); nothing else to show.
            }
        }
    }

    /// The web content process exited (crash, or the system reclaimed it): load the page again.
    /// Once per content change, so a page that crashes WebKit can't loop.
    private func webContentProcessDidTerminate() {
        guard canRecoverFromCrash else {
            return
        }
        canRecoverFromCrash = false
        display()
    }

    /// The window title is the document's title (frontmatter `title`, then the first `h1`),
    /// falling back to the file name.
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        markdownDocument?.content?.page.title ?? displayName
    }
}
