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
/// already-open window switches to it. A `--wait` token (#69) makes `waits` track the windows
/// shown for it, already-open ones included, until they close.
@MainActor
final class DocumentOpener {
    private let documentController: NSDocumentController
    private let themeSettings: ThemeSettings
    /// Shows an open failure; the document controller's alert unless a test records it.
    private let presentError: @MainActor (any Error) -> Void
    /// `mdv --wait`'s tokens and their windows (#69).
    let waits: WindowWaits

    init(
        documentController: NSDocumentController = .shared, themeSettings: ThemeSettings = .shared,
        waits: WindowWaits? = nil, presentError: (@MainActor (any Error) -> Void)? = nil
    ) {
        self.documentController = documentController
        self.themeSettings = themeSettings
        self.waits = waits ?? WindowWaits()
        self.presentError = presentError ?? { _ = documentController.presentError($0) }
    }

    /// Opens `urls` in order. `completion` runs once every file has opened or failed (tests).
    func open(_ urls: [URL], parameters: AppOpenParameters, completion: (@MainActor () -> Void)? = nil) {
        guard let waitToken = parameters.waitToken else {
            open(urls[...], themeID: usableThemeID(parameters.themeID), waitToken: nil, completion: completion)
            return
        }
        waits.begin(waitToken)
        open(urls[...], themeID: usableThemeID(parameters.themeID), waitToken: waitToken) { [weak self] in
            self?.waits.endOpening(waitToken)
            completion?()
        }
    }

    /// The theme id the windows take: one the registry has, or a `custom:` id; nil otherwise.
    func usableThemeID(_ id: String?) -> String? {
        guard let id, AppOpenParameters.isPlausibleThemeID(id) else {
            return nil
        }
        return themeSettings.registry.contains(id: id) || id.hasPrefix(CustomTheme.idPrefix) ? id : nil
    }

    private func open(
        _ urls: ArraySlice<URL>, themeID: String?, waitToken: UUID?, completion: (@MainActor () -> Void)?
    ) {
        guard let url = urls.first else {
            completion?()
            return
        }
        documentController.openDocument(withContentsOf: url, display: false) { [weak self] in
            let (document, alreadyOpen, error) = ($0, $1, $2)
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                if let error {
                    self.present(error)
                } else if let document {
                    self.show(document, alreadyOpen: alreadyOpen, themeID: themeID)
                    if let waitToken {
                        self.waits.add(document.windowControllers.compactMap(\.window), to: waitToken)
                    }
                }
                self.open(urls.dropFirst(), themeID: themeID, waitToken: waitToken, completion: completion)
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
