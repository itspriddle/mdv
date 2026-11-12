import Foundation

/// How `cmd | peep` hands standard input to the app (#68): a private file the app deletes as
/// soon as it has read it.
///
/// The CLI writes the Markdown to `<temp>/peep-stdin.XXXXXXXX/stdin.md` (`write(_:inFolder:)`):
/// a new folder from `mkdtemp(3)` (unpredictable name, created exclusively, mode 0700) holding
/// one file created exclusively with mode 0600. It sends the file in the Open Documents event's
/// direct object, so the event reaches the app like any open (an event with no files never
/// does). The app's document controller recognizes it by its shape, reads it with `take(_:)`,
/// which deletes it and its folder, and shows an untitled window instead of opening the file
/// as a document. No event parameter marks it: AppKit drops Peep's parameters on some paths, and
/// a marker would add no trust, since any sender could set it.
///
/// Trust model: any local process can send that event naming any file. `take(_:)` only reads
/// and deletes a file it can verify is a handoff, without following symbolic links: a folder
/// named `peep-stdin.*` owned by this user with no group or other permissions, holding a
/// regular file named `stdin.md`, owned by this user, with no group or other permissions and a
/// single link (so it can't be a hard link to another file). Anything else is
/// `Failure.notAHandoff` and left alone; the app then opens it as an ordinary file. The file is
/// read through the descriptor that was
/// checked, so it can't be swapped between the check and the read.
public enum StandardInputHandoff {
    /// The handoff folder's name before `mkdtemp`'s random part.
    public static let folderPrefix = "peep-stdin."
    /// The handoff file's name in its folder.
    public static let fileName = "stdin.md"
    /// The most standard input a window opens, in bytes: 10 MB, the custom preprocessor's
    /// input bound (`PreprocessorLimits.standard`), twice the largest document the app is
    /// measured with.
    public static let maximumBytes = PreprocessorLimits.standard.maximumInputBytes

    /// Why `take(_:)` didn't return a handoff's Markdown.
    public enum Failure: Error, Equatable, LocalizedError {
        /// The file isn't a handoff (or is gone); nothing was read or deleted.
        case notAHandoff
        /// A handoff larger than `maximumBytes`; it was deleted.
        case tooLarge
        /// A handoff that isn't UTF-8; it was deleted.
        case notUTF8
        /// A handoff that couldn't be read (`errno`); it was deleted.
        case unreadable(Int32)

        public var errorDescription: String? {
            switch self {
            case .notAHandoff:
                "The file isn’t standard input from the peep command."
            case .tooLarge:
                "Standard input is larger than \(maximumBytes / 1024 / 1024) MB, the most Peep opens in a window."
            case .notUTF8:
                "Standard input isn’t valid UTF-8."
            case .unreadable(let code):
                "Standard input couldn’t be read: \(String(cString: strerror(code)))."
            }
        }
    }

    // MARK: The CLI's side

    /// Writes `data` to a new handoff file in a new private folder inside `temporaryFolder`
    /// and returns the file's URL. Throws `POSIXError`; nothing is left behind on failure.
    public static func write(_ data: Data, inFolder temporaryFolder: URL) throws -> URL {
        let template = temporaryFolder.appending(path: "\(folderPrefix)XXXXXXXX").path(percentEncoded: false)
        var buffer = Array(template.utf8CString)
        let created = buffer.withUnsafeMutableBufferPointer { pointer in
            pointer.baseAddress.flatMap { mkdtemp($0) } != nil
        }
        guard created else {
            throw posixError()
        }
        let folder = URL(filePath: String(cString: buffer), directoryHint: .isDirectory)
        do {
            try writeFile(data, inFolderAt: folder.path(percentEncoded: false))
        } catch {
            remove(folder.appending(path: fileName))
            throw error
        }
        return folder.appending(path: fileName)
    }

    private static func writeFile(_ data: Data, inFolderAt folder: String) throws {
        // mkdtemp makes the folder 0700 less the umask; make sure of it.
        guard chmod(folder, 0o700) == 0 else {
            throw posixError()
        }
        let descriptor = open(
            "\(folder)/\(fileName)", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else {
            throw posixError()
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard fchmod(descriptor, 0o600) == 0 else {
            throw posixError()
        }
        try handle.write(contentsOf: data)
    }

    /// Deletes a handoff the CLI wrote, when the app never got it (the open failed).
    public static func remove(_ file: URL) {
        let folder = file.deletingLastPathComponent().path(percentEncoded: false)
        unlink(file.path(percentEncoded: false))
        rmdir(folder)
    }

    // MARK: The app's side

    /// Reads the handoff at `file` and deletes it and its folder. Throws `.notAHandoff`, having
    /// touched nothing, unless the file passes every check in the type's description; a
    /// verified handoff is deleted even when it is too large or not UTF-8.
    public static func take(_ file: URL) throws(Failure) -> String {
        // The folder's path without a trailing slash, which would make open(2) follow a link.
        let filePath = file.standardizedFileURL.path(percentEncoded: false)
        let folderPath = String(filePath.dropLast(fileName.count + 1))
        let folderName = (folderPath as NSString).lastPathComponent
        guard file.isFileURL, filePath.hasSuffix("/\(fileName)"), folderName.hasPrefix(folderPrefix),
            folderName.count > folderPrefix.count
        else {
            throw .notAHandoff
        }
        let folderDescriptor = open(folderPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folderDescriptor >= 0 else {
            throw .notAHandoff
        }
        defer { close(folderDescriptor) }
        guard isPrivate(folderDescriptor, type: S_IFDIR) else {
            throw .notAHandoff
        }
        let descriptor = openat(folderDescriptor, fileName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw .notAHandoff
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard isPrivate(descriptor, type: S_IFREG, singleLink: true) else {
            throw .notAHandoff
        }
        // Verified: it's ours to delete, whatever its contents.
        defer {
            unlinkat(folderDescriptor, fileName, 0)
            rmdir(folderPath)
        }
        let data: Data
        do {
            data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        } catch {
            let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            throw .unreadable(underlying?.domain == NSPOSIXErrorDomain ? Int32(underlying?.code ?? 0) : EIO)
        }
        guard data.count <= maximumBytes else {
            throw .tooLarge
        }
        guard let markdown = String(bytes: data, encoding: .utf8) else {
            throw .notUTF8
        }
        return markdown
    }

    /// Whether the open `descriptor` is a `type` (`S_IFDIR`, `S_IFREG`) owned by this user with
    /// no group or other permissions (and, with `singleLink`, exactly one link).
    private static func isPrivate(_ descriptor: Int32, type: mode_t, singleLink: Bool = false) -> Bool {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            return false
        }
        return info.st_mode & S_IFMT == type && info.st_uid == getuid() && info.st_mode & 0o077 == 0
            && (!singleLink || info.st_nlink == 1)
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
