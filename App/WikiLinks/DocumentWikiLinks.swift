import Foundation
import MdvCore

/// The app's side of wiki link resolution (#53): a `FolderWikiLinkResolver` over the real file
/// system for one render of one document. The search rules (document folder, then the allowed
/// root, the entry cap) live in MdvCore; this only lists folders.
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

/// Lists a folder for wiki link resolution: regular files and folders only. Symbolic links are
/// left out (so the search never leaves the allowed root or loops), and so are packages
/// (`.app`, `.rtfd`), which Finder shows as files.
struct FileSystemFolderReader: WikiLinkFolderReader {
    func entries(ofFolderAtPath path: String) -> [WikiLinkFolderEntry]? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: URL(filePath: path, directoryHint: .isDirectory), includingPropertiesForKeys: Array(keys))
        else {
            return nil
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true,
                values.isPackage != true
            else {
                return nil
            }
            if values.isDirectory == true {
                return WikiLinkFolderEntry(name: url.lastPathComponent, isFolder: true)
            }
            return values.isRegularFile == true
                ? WikiLinkFolderEntry(name: url.lastPathComponent, isFolder: false) : nil
        }
    }
}
