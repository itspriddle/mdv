import Synchronization

/// Lists folders for `FolderWikiLinkResolver`. The app reads the file system; tests use a fake,
/// so the search rules are tested in PeepCore without touching disk.
public protocol WikiLinkFolderReader: Sendable {
    /// The entries of the folder at `path` (absolute, `/`-separated), or `nil` when it can't be
    /// read. Report only regular files and folders: symbolic links and anything else are left
    /// out, so the search never follows a link out of the allowed root or around a cycle.
    func entries(ofFolderAtPath path: String) -> [WikiLinkFolderEntry]?
}

/// A regular file or folder in a listing.
public struct WikiLinkFolderEntry: Sendable, Equatable {
    public var name: String
    public var isFolder: Bool

    public init(name: String, isFolder: Bool) {
        self.name = name
        self.isFolder = isFolder
    }
}

/// The app's wiki link resolution (#53): finds a page's file in the document's folder first,
/// then anywhere under the document's allowed root (`LocalResourceRoot`), never outside it.
///
/// 1. **The document's folder:** the page's file directly in it (with folders in the name,
///    `[[guides/Setup]]`, in those folders under it).
/// 2. **The allowed root:** every folder under the root, breadth first, so the match closest to
///    the root wins. With folders in the name, the file's folder path must end with them.
///
/// Within a folder, entries are taken in name order (case-insensitive), so the result never
/// depends on the order the file system lists them. Hidden files and folders (a name starting
/// with `.`, such as `.git`) are skipped, and the reader leaves out symbolic links.
///
/// **Bounded:** the root search stops after `entryLimit` folder entries in all (10,000 by
/// default), so a huge root (a home folder with no repository is never one, but a monorepo
/// can be) can't stall a render; pages past the limit show as missing. The root is listed at
/// most once per resolver, and only if some page isn't in the document's folder. Make one
/// resolver per render: results are cached for its lifetime.
public final class FolderWikiLinkResolver: WikiLinkResolver {
    /// The default `entryLimit`.
    public static let defaultEntryLimit = 10_000

    private let documentFolder: [String]
    private let root: [String]
    private let reader: any WikiLinkFolderReader
    private let entryLimit: Int
    private let state = Mutex(State())

    private struct State {
        var listings: [String: [WikiLinkFolderEntry]] = [:]
        /// Markdown files under the root in breadth-first order, as folder paths from the root.
        var rootIndex: [IndexedFile]?
        var destinations: [WikiPage: String?] = [:]
    }

    private struct IndexedFile {
        var folders: [String]
        var name: String
    }

    /// `documentFolder` is the linking document's folder and `root` its allowed root, both
    /// absolute real paths (`LocalResourceRoot.forDocument(at:)`). A document folder outside
    /// `root` (or a `nil` root) searches the document's folder alone.
    public init(
        documentFolder: String, root: String?, reader: any WikiLinkFolderReader,
        entryLimit: Int = FolderWikiLinkResolver.defaultEntryLimit
    ) {
        let folder = Self.components(of: documentFolder)
        let root = root.map(Self.components(of:)) ?? folder
        self.documentFolder = folder
        self.root = folder.starts(with: root) ? root : folder
        self.reader = reader
        self.entryLimit = entryLimit
    }

    public func destination(for page: WikiPage) -> String? {
        state.withLock { state in
            if let cached = state.destinations[page] {
                return cached
            }
            let found = findInDocumentFolder(page, &state) ?? findUnderRoot(page, &state)
            state.destinations[page] = .some(found)
            return found
        }
    }

    // MARK: - Search

    /// Step 1: the page's folders, one by one, under the document's folder, then the file.
    private func findInDocumentFolder(_ page: WikiPage, _ state: inout State) -> String? {
        var folder = documentFolder
        for index in page.folders.indices {
            guard
                let next = listing(of: folder, &state).first(where: {
                    $0.isFolder && page.matchesFolder($0.name, at: index)
                })
            else {
                return nil
            }
            folder.append(next.name)
        }
        guard let file = listing(of: folder, &state).first(where: { !$0.isFolder && page.matches(fileName: $0.name) })
        else {
            return nil
        }
        return relativePath(to: folder + [file.name])
    }

    /// Step 2: the first match in the breadth-first root index.
    private func findUnderRoot(_ page: WikiPage, _ state: inout State) -> String? {
        let index = state.rootIndex ?? buildRootIndex(&state)
        state.rootIndex = index
        guard
            let file = index.first(where: {
                page.matches(fileName: $0.name) && page.matchesFolders(endingWith: $0.folders)
            })
        else {
            return nil
        }
        return relativePath(to: root + file.folders + [file.name])
    }

    private func buildRootIndex(_ state: inout State) -> [IndexedFile] {
        var files: [IndexedFile] = []
        var queue: [[String]] = [[]]
        var next = 0
        var budget = entryLimit
        while next < queue.count, budget > 0 {
            let folders = queue[next]
            next += 1
            let entries = listing(of: root + folders, &state).prefix(budget)
            budget -= entries.count
            for entry in entries {
                if entry.isFolder {
                    queue.append(folders + [entry.name])
                } else if WikiPage.isMarkdownFileName(entry.name) {
                    files.append(IndexedFile(folders: folders, name: entry.name))
                }
            }
        }
        return files
    }

    /// The visible entries of a folder in name order, read once per resolver.
    private func listing(of folder: [String], _ state: inout State) -> [WikiLinkFolderEntry] {
        let path = Self.path(of: folder)
        if let cached = state.listings[path] {
            return cached
        }
        let entries = (reader.entries(ofFolderAtPath: path) ?? [])
            .filter { !$0.name.hasPrefix(".") && !$0.name.isEmpty && !$0.name.contains("/") }
            .sorted { lhs, rhs in
                let left = lhs.name.lowercased()
                let right = rhs.name.lowercased()
                return left != right ? left < right : lhs.name < rhs.name
            }
        state.listings[path] = entries
        return entries
    }

    // MARK: - Paths

    /// `file` (absolute components) relative to the document's folder, `/`-separated.
    private func relativePath(to file: [String]) -> String {
        var common = 0
        while common < documentFolder.count, common < file.count - 1, documentFolder[common] == file[common] {
            common += 1
        }
        let parents = Array(repeating: "..", count: documentFolder.count - common)
        return (parents + file[common...]).joined(separator: "/")
    }

    private static func components(of path: String) -> [String] {
        path.split(separator: "/").map(String.init).filter { $0 != "." }
    }

    private static func path(of components: [String]) -> String {
        "/" + components.joined(separator: "/")
    }
}
