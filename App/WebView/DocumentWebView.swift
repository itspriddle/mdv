import AppKit
import WebKit

/// The document web view. A `WKWebView` that takes over drag and drop: files mdv can open
/// (Markdown, plain text) go to `fileDropHandler`, which opens them as new tabs; every other
/// drag is refused, so WebKit never loads or inserts what is dropped on the page.
@MainActor
final class DocumentWebView: WKWebView {
    /// Opens dropped files (already filtered to documents mdv can open). Set by the window.
    var fileDropHandler: (([URL]) -> Void)?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropOperation(for: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropOperation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {}

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !openableFiles(in: sender).isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let files = openableFiles(in: sender)
        guard !files.isEmpty, let fileDropHandler else {
            return false
        }
        fileDropHandler(files)
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {}

    override func draggingEnded(_ sender: any NSDraggingInfo) {}

    private func dropOperation(for sender: any NSDraggingInfo) -> NSDragOperation {
        fileDropHandler != nil && !openableFiles(in: sender).isEmpty ? .copy : []
    }

    private func openableFiles(in sender: any NSDraggingInfo) -> [URL] {
        DocumentDrop.openableFiles(on: sender.draggingPasteboard)
    }
}

/// Which dropped files mdv opens.
@MainActor
enum DocumentDrop {
    /// The file URLs on `pasteboard` that `controller` has a document class for (Markdown and
    /// plain text, per the app's declared document types), in order. Folders and other files
    /// are left out.
    static func openableFiles(
        on pasteboard: NSPasteboard, controller: NSDocumentController = .shared
    ) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let urls = (objects ?? []).compactMap { $0 as? URL }
        return urls.filter { url in
            guard let type = try? controller.typeForContents(of: url) else {
                return false
            }
            return controller.documentClass(forType: type) != nil
        }
    }
}
