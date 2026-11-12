import Foundation

/// Lists a folder for wiki link resolution over the real file system (the app's
/// `DocumentWikiLinks` and `peep --html`): regular files and folders only. Symbolic links are
/// left out (so the search never leaves the allowed root or loops), and so are packages
/// (`.app`, `.rtfd`), which Finder shows as files.
public struct FileSystemFolderReader: WikiLinkFolderReader {
    public init() {}

    public func entries(ofFolderAtPath path: String) -> [WikiLinkFolderEntry]? {
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

extension FolderWikiLinkResolver {
    /// A resolver over the real file system (`FileSystemFolderReader`) for one render of the
    /// document at `fileURL`: its folder (a real path) first, then `root`, its allowed root
    /// (`LocalResourceRoot.forDocument(at:)`). `nil` for a non-file URL or when the folder is
    /// gone. Cheap: nothing is read until a wiki link asks.
    public static func fileSystem(forDocumentAt fileURL: URL, root: String?) -> FolderWikiLinkResolver? {
        guard fileURL.isFileURL,
            let folder = LocalResourceRoot.realPath(fileURL.deletingLastPathComponent().path(percentEncoded: false))
        else {
            return nil
        }
        return FolderWikiLinkResolver(documentFolder: folder, root: root, reader: FileSystemFolderReader())
    }
}
