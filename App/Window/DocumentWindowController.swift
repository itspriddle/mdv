import AppKit
import PeepCore
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
    /// Whether the window's first page is still to load (the blank page shows, #32). The render
    /// progress indicator (#58) and the outline's first fill go by it.
    private(set) var isWaitingForFirstPage = true
    private var canRecoverFromCrash = true
    /// A fragment to scroll to once the page loads (a link opened this document with `#…`).
    var pendingFragment: String?
    /// The last reported reading position (source line), saved with window restoration.
    var lastSourceLine: Double?
    /// A restored reading position to scroll to once the page loads.
    var pendingSourceLine: Double?
    /// This window's remote image opt-in (#20); never saved, kept across reloads.
    let remoteImages = RemoteImageOptIn()
    /// The progress indicator for slow renders (#58, `+RenderProgress.swift`).
    let renderProgress: RenderProgress

    // MARK: Outline (#24, `DocumentWindowController+Outline.swift`)

    /// The outline sidebar's content.
    let outlineController = OutlineViewController()
    /// The sidebar item, once the window's content is built.
    var outlineSidebarItem: NSSplitViewItem?
    /// Whether the outline shows before the sidebar exists (and its last requested state).
    var wantsOutline: Bool
    /// The sidebar's width while last shown (or restored), saved with the window (#43).
    var outlineWidth: CGFloat?
    let outlinePreference: OutlinePreference

    // MARK: Status bar (`DocumentWindowController+StatusBar.swift`)

    /// The status bar's state, read by `DocumentView`.
    let statusBar: StatusBarModel
    let statusBarPreference: StatusBarPreference

    // MARK: Zoom and content width (#26, #37, #47: `+Zoom.swift`, `+ContentWidth.swift`)

    /// The zoom new windows start at; this window's level is `zoomLevel`.
    let zoomSettings: ZoomSettings
    /// This window's page zoom (restorable). Starts at Settings' default.
    var zoomLevel: Double

    /// The content width new windows start with; this window's preset is `contentWidth`.
    let contentWidthSettings: ContentWidthSettings
    /// This window's content width (restorable). Starts at Settings' default.
    var contentWidth: ContentWidth

    // MARK: Theme (#34, `DocumentWindowController+Theme.swift`)

    /// The registry and default theme this window follows.
    let themeSettings: ThemeSettings
    /// The theme the reader picked for this window with View > Theme (restorable), or nil to
    /// follow the document's theme (#54). It may name a theme that is no longer registered (a
    /// deleted custom theme); the window then shows the default (`theme`), and shows the picked
    /// one again if it comes back.
    var pickedThemeID: String?
    /// The theme the document's frontmatter names (`peep.theme`, #54), from its latest render.
    var documentThemeID: String?
    /// The theme colors of the titlebar border and status bar, read by `DocumentView`.
    let chrome = WindowChrome()
    /// Follows the window's appearance (`applyWindowChrome()`).
    var windowAppearanceObservation: NSKeyValueObservation?
    /// Settings' default theme when the window opened: what it shows with neither a pick nor a
    /// document theme. A later change to the default applies to new windows only.
    let newWindowThemeID: String

    init(
        coordinator: WebViewCoordinator = WebViewCoordinator(),
        outlinePreference: OutlinePreference = OutlinePreference(),
        statusBarPreference: StatusBarPreference = StatusBarPreference(),
        zoomSettings: ZoomSettings = .shared,
        contentWidthSettings: ContentWidthSettings = .shared,
        themeSettings: ThemeSettings = .shared,
        renderProgress: RenderProgress = RenderProgress()
    ) {
        self.coordinator = coordinator
        self.renderProgress = renderProgress
        self.outlinePreference = outlinePreference
        self.statusBarPreference = statusBarPreference
        self.zoomSettings = zoomSettings
        self.contentWidthSettings = contentWidthSettings
        self.themeSettings = themeSettings
        newWindowThemeID = themeSettings.defaultThemeIDForNewWindows
        zoomLevel = zoomSettings.defaultLevel
        contentWidth = contentWidthSettings.defaultWidth
        wantsOutline = outlinePreference.showsOutlineInNewWindows
        statusBar = StatusBarModel(
            isVisible: statusBarPreference.showsStatusBarInNewWindows, isOutlineVisible: wantsOutline)
        let window = DocumentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
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
        installZoom()
        installContentWidth()
        installTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DocumentWindowController is created in code")
    }

    override var document: AnyObject? {
        didSet {
            if document == nil, oldValue != nil {
                releaseContent()
                return
            }
            guard let markdownDocument, window?.contentViewController == nil else {
                return
            }
            let hostingController = NSHostingController(
                rootView: DocumentView(
                    document: markdownDocument, coordinator: coordinator, remoteImages: remoteImages,
                    renderProgress: renderProgress, statusBar: statusBar, chrome: chrome,
                    loadRemoteImages: { [weak self] in self?.loadRemoteImages(nil) },
                    toggleOutline: { [weak self] in self?.toggleOutline(nil) }))
            // SwiftUI sets the minimum size; the window (and later restoration) owns the size.
            hostingController.sizingOptions = [.minSize]
            hostingController.view.frame.size = window?.contentLayoutRect.size ?? .zero
            window?.contentViewController = makeSplitViewController(content: hostingController)
            if markdownDocument.content == nil {
                // Still rendering (#32): start the web view now, so the page loads fast after.
                coordinator.prepareForFirstLoad()
            }
            updateRenderProgress()
            documentContentDidChange()
        }
    }

    /// The document closed (NSDocument removes its window controllers): drop the window's
    /// content, which holds the document (`DocumentView`), the web view, and with it the web
    /// content process. AppKit can keep a window that was on screen alive for minutes after it
    /// closes (seen in the hosted tests, even for a plain `NSWindow`); without this, its
    /// document, web view, and web content process stayed alive with it.
    private func releaseContent() {
        displayTask?.cancel()
        displayTask = nil
        window?.contentViewController = nil
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
        // Before the page loads (or swaps), so a first load uses the document's theme and a live
        // reload that changed `peep.theme` swaps the stylesheet in place.
        documentThemeDidChange(page.documentThemeID)
        if !isWaitingForFirstPage {
            outlineController.show(DocumentOutline(headings: page.headings))
        }
        coordinator.documentFileURL = markdownDocument.fileURL
        // peep-doc://<window>/<path>: relative images resolve against the document and are
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
                try await loadOrSwap(page, baseURL: baseURL)
                let isFirstPage = isWaitingForFirstPage
                if isFirstPage {
                    isWaitingForFirstPage = false
                    updateRenderProgress()
                }
                await scrollToPendingFragment()
                await scrollToPendingSourceLine()
                await updateOutlinePosition()
                await refreshFind()
                if isFirstPage {
                    // Arrow keys, space, and Page Down scroll the document right away.
                    window?.makeFirstResponder(coordinator.webView)
                    await LaunchTiming.firstPageLoaded(in: coordinator)
                    // Off the first paint's critical path (#58).
                    await fillOutlineAfterFirstPaint()
                }
            } catch {
                // A newer load cancelled this one, or the web content process exited (handled
                // by `webContentProcessDidTerminate()`); nothing else to show.
            }
        }
    }

    /// Puts `page` in the web view: swapped into the loaded page in place when the base URL and
    /// CSP are unchanged, else loaded (keeping the reading position of a page already shown).
    private func loadOrSwap(_ page: RenderedPage, baseURL: URL?) async throws {
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
            LaunchTiming.mark("pageLoaded")
        }
        loadedBaseURL = baseURL
        loadedContentSecurityPolicy = page.contentSecurityPolicy
    }

    /// The web content process exited (crash, or the system reclaimed it): load the page again
    /// at the last reported reading position (the page that knew it is gone). Once per content
    /// change, so a page that crashes WebKit can't loop.
    private func webContentProcessDidTerminate() {
        guard canRecoverFromCrash else {
            return
        }
        canRecoverFromCrash = false
        if pendingSourceLine == nil {
            pendingSourceLine = lastSourceLine
        }
        display()
    }

    /// The window title is the document's title (frontmatter `title`, then the first `h1`),
    /// falling back to the file name.
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        markdownDocument?.content?.page.title ?? displayName
    }
}
