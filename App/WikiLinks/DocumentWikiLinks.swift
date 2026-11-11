import Foundation
import MdvCore

/// The app's side of wiki link resolution (#53): a `FolderWikiLinkResolver` over the real file
/// system for one render of one document. The search rules (document folder, then the allowed
/// root, the entry cap) and the folder reader (`FileSystemFolderReader`) live in MdvCore.
enum DocumentWikiLinks {
    /// A resolver for one render of the document at `fileURL`, searching its folder and then
    /// `linkRoot` (its allowed root, `DocumentContent.linkRoot(forDocumentAt:)`). `nil` without a
    /// file or when its folder is gone. Cheap: nothing is read until a wiki link asks.
    static func resolver(forDocumentAt fileURL: URL?, linkRoot: String?) -> FolderWikiLinkResolver? {
        guard let fileURL, fileURL.isFileURL,
            let folder = realPath(fileURL.deletingLastPathComponent().path(percentEncoded: false))
        else {
            return nil
        }
        return FolderWikiLinkResolver(documentFolder: folder, root: linkRoot, reader: FileSystemFolderReader())
    }

    /// `realpath(3)`, so the folder compares with the allowed root (also a real path).
    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else {
            return nil
        }
        defer { free(resolved) }
        return String(validatingCString: resolved)
    }
}
