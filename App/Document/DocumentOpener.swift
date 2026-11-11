import AppKit
import MdvCore

/// Opens the files of an Open Documents Apple Event: Finder, the Dock, `open`, and `mdv FILE`
/// (#67), which adds `AppOpenParameters` to the event (`AppOpenEvent`). `AppDelegate`'s
/// `application(_:open:)` calls it with the parameters of the event being handled.
///
/// Files open one after another (so a repeated file finds the first one open) through the
/// document controller, as AppKit would open them; an already-open file brings its window
/// forward. A failure is presented as AppKit presents it.
///
/// The parameters are untrusted (any local process can send the event) and presentation-only:
/// a theme id is used only if it is registered or a `custom:` id (whose file may load later,
/// and which falls back to Settings' default until it does), and becomes each window's View >
/// Theme pick, so it beats the document's `mdv.theme` and restoration keeps it. An
/// already-open window switches to it.
@MainActor
final class DocumentOpener {
    private let documentController: NSDocumentController
    private let themeSettings: ThemeSettings
    /// Shows an open failure; the document controller's alert unless a test records it.
    private let presentError: @MainActor (any Error) -> Void

    init(
        documentController: NSDocumentController = .shared, themeSettings: ThemeSettings = .shared,
        presentError: (@MainActor (any Error) -> Void)? = nil
    ) {
        self.documentController = documentController
        self.themeSettings = themeSettings
        self.presentError = presentError ?? { _ = documentController.presentError($0) }
    }

    /// Opens `urls` in order. `completion` runs once every file has opened or failed (tests).
    func open(_ urls: [URL], parameters: AppOpenParameters, completion: (@MainActor () -> Void)? = nil) {
        open(urls[...], themeID: usableThemeID(parameters.themeID), completion: completion)
    }

    /// The theme id the windows take: one the registry has, or a `custom:` id; nil otherwise.
    func usableThemeID(_ id: String?) -> String? {
        guard let id, AppOpenParameters.isPlausibleThemeID(id) else {
            return nil
        }
        return themeSettings.registry.contains(id: id) || id.hasPrefix(CustomTheme.idPrefix) ? id : nil
    }

    private func open(_ urls: ArraySlice<URL>, themeID: String?, completion: (@MainActor () -> Void)?) {
        guard let url = urls.first else {
            completion?()
            return
        }
        documentController.openDocument(withContentsOf: url, display: false) { [weak self] document, alreadyOpen, error in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                if let error {
                    self.present(error)
                } else if let document {
                    self.show(document, alreadyOpen: alreadyOpen, themeID: themeID)
                }
                self.open(urls.dropFirst(), themeID: themeID, completion: completion)
            }
        }
    }

    /// Shows `document`, with the theme picked before a new window first appears.
    private func show(_ document: NSDocument, alreadyOpen: Bool, themeID: String?) {
        if !alreadyOpen, document.windowControllers.isEmpty {
            document.makeWindowControllers()
        }
        if let themeID {
            for controller in document.windowControllers.compactMap({ $0 as? DocumentWindowController }) {
                controller.setTheme(id: themeID)
            }
        }
        document.showWindows()
    }

    private func present(_ error: any Error) {
        if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
            return
        }
        presentError(error)
    }
}
