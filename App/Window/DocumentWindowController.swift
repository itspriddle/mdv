import AppKit
import MdvCore
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
    /// The CSP of the loaded page. A swap keeps it, so a page that needs another one is loaded.
    private var loadedContentSecurityPolicy: ContentSecurityPolicy?
    private var hasShownPage = false
    private var canRecoverFromCrash = true
    /// A fragment to scroll to once the page loads (a link opened this document with `#…`).
    var pendingFragment: String?
    /// The last reported reading position (source line), saved with window restoration.
    var lastSourceLine: Double?
    /// A restored reading position to scroll to once the page loads.
    var pendingSourceLine: Double?
    /// This window's remote image opt-in (#20); never saved, kept across reloads.
    let remoteImages = RemoteImageOptIn()

    // MARK: Outline (#24, `DocumentWindowController+Outline.swift`)

    /// The outline sidebar's content.
    let outlineController = OutlineViewController()
    /// The sidebar item, once the window's content is built.
    var outlineSidebarItem: NSSplitViewItem?
    /// Whether the outline shows before the sidebar exists (and its last requested state).
    var wantsOutline: Bool
    let outlinePreference: OutlinePreference

    init(
        coordinator: WebViewCoordinator = WebViewCoordinator(),
        outlinePreference: OutlinePreference = OutlinePreference()
    ) {
        self.coordinator = coordinator
        self.outlinePreference = outlinePreference
        wantsOutline = outlinePreference.showsOutlineInNewWindows
        let window = DocumentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.backgroundColor = .themeBackground
        window.minSize = NSSize(width: 480, height: 360)
        window.center()
        super.init(window: window)
        coordinator.webContentProcessDidTerminate = { [weak self] in
            self?.webContentProcessDidTerminate()
        }
        installLinkHandling()
        configureForOpening(window)
        installScrollTracking()
        installOutline()
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
                rootView: DocumentView(
                    document: markdownDocument, coordinator: coordinator, remoteImages: remoteImages,
                    loadRemoteImages: { [weak self] in self?.loadRemoteImages(nil) }))
            // SwiftUI sets the minimum size; the window (and later restoration) owns the size.
            hostingController.sizingOptions = [.minSize]
            hostingController.view.frame.size = window?.contentLayoutRect.size ?? .zero
            window?.contentViewController = makeSplitViewController(content: hostingController)
            documentContentDidChange()
        }
    }

    /// Called by `MarkdownDocument.setContent(_:)` after every (re)load, and once when the
    /// window is attached to its document.
    ///
    /// Live reload keeps the reading position: content is swapped into the loaded page in place
    /// (`updateContent(with:baseURL:)`), with no reload and no flash. Only when the base URL
    /// changed (the file moved) or the CSP did (remote images opted in, #20) is the page loaded
    /// again, and the position restored after.
    func documentContentDidChange() {
        canRecoverFromCrash = true
        display()
    }

    /// Shows the document's current content. Display tasks run one at a time, in order; a task
    /// that a newer one superseded before it started is skipped.
    private func display() {
        guard let markdownDocument, let page = displayedPage else {
            return
        }
        synchronizeWindowTitleWithDocumentName()
        outlineController.show(DocumentOutline(headings: page.headings))
        coordinator.documentFileURL = markdownDocument.fileURL
        // mdv-doc://<window>/<path>: relative images resolve against the document and are
        // served only from its allowed root (`LocalResourceSchemeHandler`). A moved file gets a
        // new base URL (and root), so the page is loaded again rather than swapped in place.
        let baseURL = coordinator.documentURL(forFileAt: markdownDocument.fileURL)
        let previous = displayTask
        previous?.cancel()
        displayTask = Task { [coordinator, weak self] in
            await previous?.value
            guard !Task.isCancelled, let self else {
                return
            }
            do {
                if coordinator.hasLoadedPage, baseURL == loadedBaseURL,
                    page.contentSecurityPolicy == loadedContentSecurityPolicy
                {
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
                loadedContentSecurityPolicy = page.contentSecurityPolicy
                await scrollToPendingFragment()
                await scrollToPendingSourceLine()
                await updateOutlinePosition()
                await refreshFind()
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
