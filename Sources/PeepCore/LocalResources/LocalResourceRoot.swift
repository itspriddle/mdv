import Foundation

/// The folder a document may load local images from (its "allowed root").
///
/// The rule: **the root of the enclosing git work tree, else the document's folder.** Walking up
/// from the document's folder (symlinks resolved), the first folder that contains a `.git`
/// entry (a directory, or a file for worktrees and submodules) is the root. If there is none,
/// or it is the home folder or `/` (a dotfiles repository would otherwise expose every image
/// under home), the root is the document's own folder.
///
/// Why the repository: docs in a repo commonly use `../images/x.png`, and GitHub resolves
/// relative paths within the repository. The repository is one trust domain with the document,
/// and only images are ever served from it.
public enum LocalResourceRoot {
    /// The allowed root for the document at `fileURL`, as a real path (no symlinks). Nil when
    /// the document's folder doesn't exist.
    public static func forDocument(
        at fileURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        guard fileURL.isFileURL,
            let folder = realPath(fileURL.deletingLastPathComponent().path(percentEncoded: false))
        else {
            return nil
        }
        let home = realPath(homeDirectory.path(percentEncoded: false))
        guard let repository = enclosingRepository(of: folder), repository != "/", repository != home else {
            return folder
        }
        return repository
    }

    /// The nearest folder at or above `folder` that contains `.git`.
    static func enclosingRepository(of folder: String) -> String? {
        var current = folder
        while true {
            let marker = (current as NSString).appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: marker) {
                return current
            }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current, !parent.isEmpty else {
                return nil
            }
            current = parent
        }
    }

    /// `realpath(3)`: absolute, with `.`, `..`, and every symlink resolved. Nil if the path
    /// doesn't exist.
    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else {
            return nil
        }
        defer { free(resolved) }
        return String(validatingCString: resolved)
    }
}
