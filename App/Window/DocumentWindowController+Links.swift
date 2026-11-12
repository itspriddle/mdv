import AppKit
import PeepCore

/// Performs the link actions `LinkPolicy` decides (#19). In-page scrolling stays in
/// `WebViewCoordinator`; everything that opens something lands here.
extension DocumentWindowController {
    /// Routes the coordinator's link actions to this window. Called once from `init`.
    func installLinkHandling() {
        coordinator.linkHandler = { [weak self] action, opening in
            self?.perform(action, opening: opening)
        }
    }

    func perform(_ action: LinkAction, opening: LinkOpening) {
        switch action {
        case .scrollToFragment(let fragment):
            Task { [coordinator] in
                try? await coordinator.scroll(toFragment: fragment)
            }
        case .openDocument(let file, let fragment):
            openDocument(file, fragment: fragment, opening: opening)
        case .revealInFinder(let file):
            guard Self.fileExists(file) else {
                showLinkMessage("Couldn’t find “\(file.lastPathComponent)”")
                return
            }
            guard UITestHooks.opensLinksOutsideApp else {
                showLinkMessage("UI test: would show in Finder: \(file.path(percentEncoded: false))")
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([file])
        case .openExternal(let url):
            guard UITestHooks.opensLinksOutsideApp else {
                showLinkMessage("UI test: would open \(url.absoluteString)")
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = opening == .normal
            NSWorkspace.shared.open(url, configuration: configuration) { [weak self] _, error in
                guard let error else {
                    return
                }
                let description = error.localizedDescription
                Task { @MainActor in
                    self?.showLinkMessage(description)
                }
            }
        case .blocked:
            showLinkMessage(LinkPolicy.statusText(for: action))
        }
    }

    /// Opens a linked Markdown file in Peep. A plain click opens it like any document (the system
    /// tab preference decides window or tab); `.newTab` adds it as a tab of this window. An
    /// already-open document is brought forward. Then scrolls to `fragment`, if any.
    ///
    /// Errors (missing file, unreadable) show in the link status overlay, not a modal alert.
    private func openDocument(_ file: URL, fragment: String?, opening: LinkOpening) {
        guard Self.fileExists(file) else {
            showLinkMessage("Couldn’t open “\(file.lastPathComponent)”: the file doesn’t exist")
            return
        }
        let inNewTab = opening == .newTab
        NSDocumentController.shared.openDocument(withContentsOf: file, display: !inNewTab) { [weak self] in
            let (document, alreadyOpen, error) = ($0, $1, $2)
            MainActor.assumeIsolated {
                self?.didOpenLinkedDocument(
                    document, alreadyOpen: alreadyOpen, error: error, file: file, fragment: fragment, inNewTab: inNewTab
                )
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func didOpenLinkedDocument(
        _ document: NSDocument?, alreadyOpen: Bool, error: (any Error)?, file: URL, fragment: String?, inNewTab: Bool
    ) {
        if let error {
            showLinkMessage("Couldn’t open “\(file.lastPathComponent)”: \(error.localizedDescription)")
            return
        }
        guard let document = document as? MarkdownDocument else {
            return
        }
        if inNewTab {
            showInNewTab(document, alreadyOpen: alreadyOpen)
        }
        if let fragment {
            for case let controller as DocumentWindowController in document.windowControllers {
                controller.scrollWhenLoaded(toFragment: fragment)
            }
        }
    }

    private func showInNewTab(_ document: MarkdownDocument, alreadyOpen: Bool) {
        if document.windowControllers.isEmpty {
            document.makeWindowControllers()
        }
        if !alreadyOpen, let window, let newWindow = document.windowControllers.first?.window, newWindow !== window {
            window.addTabbedWindow(newWindow, ordered: .above)
        }
        document.showWindows()
    }

    /// Scrolls to `fragment` now if the page is loaded, else right after the first load.
    func scrollWhenLoaded(toFragment fragment: String) {
        guard coordinator.hasLoadedPage else {
            pendingFragment = fragment
            return
        }
        Task { [coordinator] in
            try? await coordinator.scroll(toFragment: fragment)
        }
    }

    /// Applies a fragment that arrived before the page loaded. Called after each load.
    func scrollToPendingFragment() async {
        guard let fragment = pendingFragment else {
            return
        }
        pendingFragment = nil
        _ = try? await coordinator.scroll(toFragment: fragment)
    }

    private func showLinkMessage(_ message: String) {
        coordinator.linkStatus.show(message: message)
    }

    private static func fileExists(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
    }
}
