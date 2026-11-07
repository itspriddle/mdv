import AppKit
import MdvCore

/// The app delegate. mdv uses the AppKit app lifecycle: `NSDocumentController` opens
/// `MarkdownDocument`s, each shown in a `DocumentWindowController`, and `MainMenu` builds the
/// menu bar. SwiftUI draws window content only.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let defaultViewerOffer = DefaultViewerOfferController()
    /// Custom themes (#35); nil where they are off (hosted unit tests, UI tests without a
    /// themes folder).
    private(set) var customThemes: CustomThemeLibrary?

    func applicationWillFinishLaunching(_ notification: Notification) {
        LaunchTiming.mark("willFinishLaunching")
        MainMenu.install()
        // Before restoration: restored windows showing a custom theme switch to it as soon as
        // the first load (off the main thread) lands.
        if let folder = CustomThemeLibrary.folderURL {
            let library = CustomThemeLibrary(folder: folder, settings: .shared)
            library.start()
            customThemes = library
        }
        // Load highlight.js into its JavaScriptCore context off the main thread, so the first
        // document doesn't pay for it.
        Task.detached(priority: .utility) {
            HighlightJSHighlighter.shared.prepare()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchTiming.mark("didFinishLaunching")
        if !Self.isHostingUnitTests {
            defaultViewerOffer.start()
        }
        openUITestDocuments(UITestHooks.documentsToOpen[...])
    }

    /// Opens the UI test's documents one after another, so a repeated path finds the first open.
    private func openUITestDocuments(_ urls: ArraySlice<URL>) {
        guard let url = urls.first else {
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
            if let error {
                NSLog("mdv: UI test document failed to open: %@", error.localizedDescription)
            }
            MainActor.assumeIsolated {
                self?.openUITestDocuments(urls.dropFirst())
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// A viewer has no untitled documents. When launched with no documents to open and no
    /// windows to restore, or reactivated from the Dock with no visible windows, show the Open
    /// panel instead (#22). Opening files (Finder, Dock drop, `mdv FILE`) and restoring windows
    /// skip this, as AppKit only asks when nothing else opened.
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

    /// View > Theme > Open Themes Folder: creates the folder if needed and shows it in Finder.
    @objc func openThemesFolder(_ sender: Any?) {
        customThemes?.openFolder()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openThemesFolder(_:)) {
            return customThemes != nil
        }
        return defaultViewerOffer.validateMenuItem(menuItem)
    }

    /// Whether the app is the host for `AppTests`, where a modal Open panel would block the run.
    static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
