import AppKit
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
///   every other open path, without mdv registering for them (`ExtensionlessText`, #41).
@MainActor
final class DocumentController: NSDocumentController {
    /// The Open panel's delegate while the panel is up (a panel holds its delegate weakly).
    private var openPanelFilter: OpenPanelFilter?

    /// Whether opened documents go in Open Recent. Off when the app runs under tests, which
    /// share the bundle ID (and so the recents list) with the user's real mdv.
    static var recordsRecentDocuments: Bool {
        !AppDelegate.isHostingUnitTests && !UITestHooks.isUITesting
    }

    override func noteNewRecentDocumentURL(_ url: URL) {
        guard Self.recordsRecentDocuments else {
            return
        }
        super.noteNewRecentDocumentURL(url)
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

    /// Whether `url` is a file mdv opens: one whose type (`typeForContents(of:)`) has a
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
