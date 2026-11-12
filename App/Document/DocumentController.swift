import AppKit
import PeepCore
import UniformTypeIdentifiers

/// The app's `NSDocumentController` (created in `main.swift`, before anything touches
/// `NSDocumentController.shared`, so it becomes the shared controller).
///
/// AppKit's defaults handle opening (Finder, Open panel, Dock drops, Open Recent) and bring an
/// already-open document forward. This subclass tightens three of them and widens one:
/// - an already-open file is found by file identity, not URL spelling (symlinks, `/private/tmp`
///   vs `/tmp`, case), so it focuses its window instead of opening a duplicate;
/// - window restoration skips documents whose file is gone or in the Trash, quietly;
/// - tests (hosted unit tests and UI tests) don't add to the user's Open Recent list;
/// - extensionless text files (`README`) open as plain text from the Open panel, drops, and
///   every other open path, without Peep registering for them (`ExtensionlessText`, #41).
@MainActor
final class DocumentController: NSDocumentController {
    /// The Open panel's delegate while the panel is up (a panel holds its delegate weakly).
    private var openPanelFilter: OpenPanelFilter?

    /// Whether opened documents go in Open Recent. Off when the app runs under tests, which
    /// share the bundle ID (and so the recents list) with the user's real Peep.
    static var recordsRecentDocuments: Bool {
        !AppDelegate.isHostingUnitTests && !UITestHooks.isUITesting
    }

    override func noteNewRecentDocumentURL(_ url: URL) {
        guard Self.recordsRecentDocuments else {
            return
        }
        super.noteNewRecentDocumentURL(url)
    }

    /// Opens `url`, unless it is `cmd | peep`'s standard input handoff (#68): a file that
    /// `StandardInputHandoff.take(_:)` verifies is one (by its shape: name, owner, permissions,
    /// one link, no symbolic links) is read, deleted, and opened as an untitled document
    /// (`MarkdownDocument(standardInput:)`) that never enters Open Recent. Recognizing it here,
    /// not by an event parameter, covers every path an Open Documents event takes (Peep's
    /// direct event through `DocumentOpener`, and AppKit's own handling).
    /// A file that isn't a handoff opens as usual; a handoff too large or not UTF-8 is deleted
    /// and fails the open with its reason.
    ///
    /// A file AppKit opens for an Open Documents event that carries Peep's parameters
    /// (`peep --theme`, `--wait` through Launch Services, #67/#69) goes to `eventOpener`, which
    /// applies them. AppKit handles those events itself and never calls the app delegate's
    /// `application(_:open:)` for Peep's document types, and while an earlier open is in flight
    /// it opens the files later, when the event is no longer current: so the parameters come
    /// from `eventLog`, recorded as the event arrived, else from the current event.
    override func openDocument(
        withContentsOf url: URL, display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        guard displayDocument, let eventOpener,
            let parameters = eventLog.take(for: url)
                ?? Self.openDocumentsParameters(NSAppleEventManager.shared().currentAppleEvent)
        else {
            openFile(url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        eventOpener.openForOpenDocumentsEvent(
            parameters: parameters,
            open: { [weak self] completion in
                guard let self else {
                    completion(nil, false, CocoaError(.userCancelled))
                    return
                }
                self.openFile(url, display: false, completionHandler: completion)
            },
            completion: completionHandler)
    }

    /// Opens the files of Open Documents events that carry Peep's parameters (the app
    /// delegate's `DocumentOpener`; nil in tests that make their own controller).
    weak var eventOpener: DocumentOpener?

    /// The parameters of Open Documents events as they arrived (`OpenDocumentsEventTap`).
    let eventLog = OpenDocumentsEventLog()

    /// Peep's parameters in `event` when it is a standard Open Documents event (`aevt/odoc`) that
    /// carries any; nil otherwise. (Peep's direct event goes to `DocumentOpener` itself.)
    nonisolated static func openDocumentsParameters(_ event: NSAppleEventDescriptor?) -> AppOpenParameters? {
        guard let event, event.eventClass == AEEventClass(kCoreEventClass),
            event.eventID == AEEventID(kAEOpenDocuments)
        else {
            return nil
        }
        let parameters = AppOpenParameters(event: event)
        return parameters == AppOpenParameters() ? nil : parameters
    }

    /// `openDocument(withContentsOf:display:completionHandler:)` without Peep's event
    /// parameters: the standard input handoff, else AppKit's open.
    private func openFile(
        _ url: URL, display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        guard url.isFileURL, url.lastPathComponent == StandardInputHandoff.fileName else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        let source: String
        do {
            source = try StandardInputHandoff.take(url)
        } catch .notAHandoff {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        } catch {
            completionHandler(nil, false, error)
            return
        }
        let document = MarkdownDocument(standardInput: source)
        addDocument(document)
        if displayDocument {
            document.makeWindowControllers()
            document.showWindows()
        }
        completionHandler(document, false, nil)
    }

    /// The open document for `url`: AppKit's URL match, else a document whose file is the same
    /// file (`isSameFile`).
    override func document(for url: URL) -> NSDocument? {
        if let document = super.document(for: url) {
            return document
        }
        guard url.isFileURL else {
            return nil
        }
        return documents.first { document in
            document.fileURL.map { Self.isSameFile($0, url) } ?? false
        }
    }

    /// Restoration (and autosave recovery) reopens documents here. A document whose file was
    /// deleted or moved to the Trash is skipped: a cancelled error, which AppKit never presents.
    override func reopenDocument(
        for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        guard Self.canRestore(contentsURL) else {
            completionHandler(nil, false, CocoaError(.userCancelled))
            return
        }
        super.reopenDocument(
            for: urlOrNil, withContentsOf: contentsURL, display: displayDocument,
            completionHandler: completionHandler)
    }

    /// The file's type, as AppKit decides it, except that an extensionless text file whose
    /// type has no document class (`public.data`) is plain text. Opening, drops
    /// (`DocumentDrop`), and the Open panel all ask this.
    override func typeForContents(of url: URL) throws -> String {
        let type = try super.typeForContents(of: url)
        guard documentClass(forType: type) == nil, ExtensionlessText.isPlainText(at: url) else {
            return type
        }
        return UTType.plainText.identifier
    }

    /// Whether `url` is a file Peep opens: one whose type (`typeForContents(of:)`) has a
    /// document class. Folders are not.
    func canOpen(_ url: URL) -> Bool {
        guard let type = try? typeForContents(of: url) else {
            return false
        }
        return documentClass(forType: type) != nil
    }

    /// The Open panel filters by type, which leaves `README` greyed out (its type is
    /// `public.data`). Run it unfiltered and let `canOpen(_:)` enable files instead, so the
    /// panel accepts exactly what the other open paths accept.
    override func beginOpenPanel(
        _ openPanel: NSOpenPanel, forTypes inTypes: [String]?,
        completionHandler: @escaping (Int) -> Void
    ) {
        let filter = OpenPanelFilter(controller: self)
        openPanelFilter = filter
        openPanel.delegate = filter
        super.beginOpenPanel(openPanel, forTypes: nil) { [weak self] result in
            MainActor.assumeIsolated {
                if self?.openPanelFilter === filter {
                    self?.openPanelFilter = nil
                }
            }
            completionHandler(result)
        }
    }

    // MARK: Policy

    /// Whether two file URLs name the same file: equal file resource identifiers (which see
    /// through symlinks, hard links, and case-insensitive names), else equal resolved paths.
    nonisolated static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        guard lhs.isFileURL, rhs.isFileURL else {
            return false
        }
        // Fresh URLs: resource values are cached per URL instance and may be stale.
        let left = URL(filePath: lhs.path(percentEncoded: false)).resolvingSymlinksInPath()
        let right = URL(filePath: rhs.path(percentEncoded: false)).resolvingSymlinksInPath()
        if let leftID = fileIdentifier(left), let rightID = fileIdentifier(right) {
            return leftID.isEqual(rightID)
        }
        return left.standardizedFileURL.path(percentEncoded: false)
            == right.standardizedFileURL.path(percentEncoded: false)
    }

    /// Whether restoration should reopen the document at `url`: it exists and isn't in the
    /// Trash. (Restoration finds files by bookmark, which follows a file into the Trash.)
    nonisolated static func canRestore(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL, fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return false
        }
        var relationship = FileManager.URLRelationship.other
        if (try? fileManager.getRelationship(&relationship, of: .trashDirectory, in: .allDomainsMask, toItemAt: url))
            != nil, relationship == .contains
        {
            return false
        }
        return true
    }

    nonisolated private static func fileIdentifier(_ url: URL) -> (any NSObjectProtocol)? {
        (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
    }
}

/// Enables the Open panel's files that `DocumentController.canOpen(_:)` accepts, and every
/// folder (to navigate into) that isn't a package.
@MainActor
final class OpenPanelFilter: NSObject, NSOpenSavePanelDelegate {
    private weak var controller: DocumentController?

    init(controller: DocumentController) {
        self.controller = controller
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if values?.isDirectory == true {
            return values?.isPackage != true
        }
        return controller?.canOpen(url) ?? false
    }
}
