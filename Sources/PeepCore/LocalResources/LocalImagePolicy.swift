import Foundation

/// An image approved by `LocalImagePolicy`, ready to serve.
public struct LocalImage: Sendable, Equatable {
    public let data: Data
    public let format: ImageFormat

    public var mimeType: String { format.mimeType }
}

/// Decides, for one window, which `peep-doc` requests are served from disk. Every rule must pass;
/// any failure is the same `nil` (the handler answers a bare 404, with no reason given):
///
/// 1. The URL is this window's (`DocumentURLScheme.filePath(from:token:)`: scheme, token, and a
///    lexically clean absolute path; encoded `%2e%2e` and `%2f` are refused).
/// 2. The requested name has an image extension (`ImageFormat(fileExtension:)`).
/// 3. With every symlink resolved, the file is inside `root` (`realpath`), and is a regular
///    file (no directories, FIFOs, or devices) no larger than `maximumSize`.
/// 4. The file actually opened is still inside `root` (`F_GETPATH` on the open descriptor), so
///    swapping in a symlink between the check and the open doesn't escape.
/// 5. The resolved name has an image extension, and the content sniffs as that same format.
///
/// Pure Foundation and POSIX, no WebKit: the app's `WKURLSchemeHandler` only forwards requests
/// here, so the whole policy is unit tested in `PeepCoreTests`.
public struct LocalImagePolicy: Sendable, Equatable {
    /// The window this policy answers (`DocumentURLScheme`'s host).
    public let token: String
    /// The allowed root, as a real path (see `LocalResourceRoot`).
    public let root: String
    /// Larger files are refused.
    public let maximumSize: Int

    public static let defaultMaximumSize = 32 * 1024 * 1024

    /// - Parameter root: the allowed root folder. It is resolved to a real path here; nil if it
    ///   doesn't exist.
    public init?(token: String, root: String, maximumSize: Int = defaultMaximumSize) {
        guard let realRoot = LocalResourceRoot.realPath(root) else {
            return nil
        }
        self.token = token
        self.root = realRoot
        self.maximumSize = maximumSize
    }

    /// The policy for the document at `fileURL` in the window `token`, with the root from
    /// `LocalResourceRoot`. Nil when the document's folder doesn't exist.
    public init?(token: String, documentAt fileURL: URL) {
        guard let root = LocalResourceRoot.forDocument(at: fileURL) else {
            return nil
        }
        self.init(token: token, root: root)
    }

    /// The URL to load the document's page at, so relative URLs resolve against it. The folder
    /// part is resolved to a real path, matching `root`; the file name is kept as given.
    public func documentURL(forFileAt fileURL: URL) -> URL? {
        guard let folder = LocalResourceRoot.realPath(fileURL.deletingLastPathComponent().path(percentEncoded: false))
        else {
            return nil
        }
        let path = (folder as NSString).appendingPathComponent(fileURL.lastPathComponent)
        return DocumentURLScheme.url(token: token, filePath: path)
    }

    /// The image `url` names, if the policy allows serving it; otherwise nil.
    public func image(for url: URL) -> LocalImage? {
        guard let requested = DocumentURLScheme.filePath(from: url, token: token),
            ImageFormat(fileExtension: (requested as NSString).pathExtension) != nil,
            let resolved = LocalResourceRoot.realPath(requested), contains(resolved)
        else {
            return nil
        }
        return read(resolved)
    }

    /// Whether the real path `path` is `root` or inside it.
    func contains(_ path: String) -> Bool {
        root == "/" || path == root || path.hasPrefix(root + "/")
    }

    // MARK: Reading

    private func read(_ path: String) -> LocalImage? {
        // O_NONBLOCK: opening a FIFO named `x.png` must not hang. O_NOFOLLOW: the final
        // component was just resolved; if it is a symlink now, something changed underneath.
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            return nil
        }
        defer { close(descriptor) }

        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_size <= maximumSize,
            let openedPath = Self.path(of: descriptor), contains(openedPath),
            let format = ImageFormat(fileExtension: (openedPath as NSString).pathExtension),
            let data = Self.readAll(descriptor, limit: maximumSize),
            ImageFormat.sniff(data) == format
        else {
            return nil
        }
        return LocalImage(data: data, format: format)
    }

    /// The real path of the open file (`F_GETPATH`).
    private static func path(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = buffer.withUnsafeMutableBytes { bytes -> Int32 in
            guard let base = bytes.baseAddress else {
                return -1
            }
            return fcntl(descriptor, F_GETPATH, base)
        }
        guard result != -1 else {
            return nil
        }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.flatMap { String(validatingCString: $0) }
        }
    }

    /// Reads to end of file; nil on error or past `limit` bytes (the file grew).
    private static func readAll(_ descriptor: Int32, limit: Int) -> Data? {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = chunk.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            if count == 0 {
                return data
            }
            data.append(contentsOf: chunk[0..<count])
            if data.count > limit {
                return nil
            }
        }
    }
}
