import AppKit

/// Window setup for opening documents (#22): restoration identity, native tabs, and files
/// dropped on the window.
extension DocumentWindowController {
    /// The identifier of every document window. `NSDocument` restores a window by finding the
    /// one with the saved identifier among its window controllers' windows.
    static let windowIdentifier = NSUserInterfaceItemIdentifier("MarkdownDocumentWindow")

    /// Groups document windows into one set of native tabs (Window > Merge All Windows).
    static let tabbingIdentifier: NSWindow.TabbingIdentifier = "MarkdownDocument"

    /// Configures `window` for restoration and tabs, and routes file drops. Called once from
    /// `init`.
    ///
    /// Tabbing is `.automatic`: the system "Prefer tabs when opening documents" setting decides
    /// whether a new document opens as a window or a tab, as in Preview and TextEdit.
    func configureForOpening(_ window: NSWindow) {
        window.identifier = Self.windowIdentifier
        window.isRestorable = true
        window.tabbingMode = .automatic
        window.tabbingIdentifier = Self.tabbingIdentifier
        coordinator.webView.fileDropHandler = { [weak self] files in
            self?.openDroppedFiles(files)
        }
    }

    /// Opens files dropped on this window as new tabs of it, in order. A file that is already
    /// open brings its window forward instead. Failures show in the link status overlay.
    ///
    /// - Parameter anchor: the tab the next file goes after (default: this window's).
    func openDroppedFiles(_ files: [URL], after anchor: NSWindow? = nil) {
        guard let file = files.first else {
            return
        }
        let remaining = Array(files.dropFirst())
        NSDocumentController.shared.openDocument(withContentsOf: file, display: false) { [weak self] in
            let (document, alreadyOpen, error) = ($0, $1, $2)
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                var next = anchor
                if let error {
                    self.coordinator.linkStatus.show(
                        message: "Couldn’t open “\(file.lastPathComponent)”: \(error.localizedDescription)")
                } else if let document = document as? MarkdownDocument {
                    next =
                        self.showDroppedDocument(document, alreadyOpen: alreadyOpen, after: anchor ?? self.window)
                        ?? anchor
                }
                self.openDroppedFiles(remaining, after: next)
            }
        }
    }

    /// Shows `document`: an already-open one in its own window, a new one as a tab after
    /// `anchor`. Returns the new tab's window.
    private func showDroppedDocument(_ document: MarkdownDocument, alreadyOpen: Bool, after anchor: NSWindow?)
        -> NSWindow?
    {
        guard !alreadyOpen else {
            document.showWindows()
            return nil
        }
        if document.windowControllers.isEmpty {
            document.makeWindowControllers()
        }
        let newWindow = document.windowControllers.first?.window
        if let anchor, let newWindow, newWindow !== anchor {
            anchor.addTabbedWindow(newWindow, ordered: .above)
        }
        document.showWindows()
        return newWindow
    }
}
