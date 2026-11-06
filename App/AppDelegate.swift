import AppKit
import MdvCore

/// The app delegate. mdv uses the AppKit app lifecycle: `NSDocumentController` opens
/// `MarkdownDocument`s, each shown in a `DocumentWindowController`, and `MainMenu` builds the
/// menu bar. SwiftUI draws window content only.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let defaultViewerOffer = DefaultViewerOfferController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        // Load highlight.js into its JavaScriptCore context off the main thread, so the first
        // document doesn't pay for it.
        Task.detached(priority: .utility) {
            HighlightJSHighlighter.shared.prepare()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Self.isHostingUnitTests {
            defaultViewerOffer.start()
        }
        if let url = UITestHooks.documentToOpen {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error {
                    NSLog("mdv: UI test document failed to open: %@", error.localizedDescription)
                }
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// A viewer has no untitled documents. When launched (or reactivated from the Dock) with no
    /// windows, show the Open panel instead, as `DocumentGroup(viewing:)` did.
    ///
    /// TODO(#22): settle launch, Dock, and restoration behavior for the opening flows.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !Self.isHostingUnitTests && !UITestHooks.isUITesting
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// App menu: "Make mdv the Default Markdown Viewer" (`DefaultViewerMenu`).
    @objc func makeDefaultMarkdownViewer(_ sender: Any?) {
        defaultViewerOffer.makeDefaultMarkdownViewer(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        defaultViewerOffer.validateMenuItem(menuItem)
    }

    /// Whether the app is the host for `AppTests`, where a modal Open panel would block the run.
    static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
