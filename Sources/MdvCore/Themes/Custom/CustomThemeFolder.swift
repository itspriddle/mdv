import Darwin
import Foundation

/// The custom themes folder (#35): every `*.css` file in it is a theme (`CustomTheme`).
///
/// Reading is defensive. Hidden files and other extensions are ignored; the rest are read
/// only if they are regular files (symbolic links, folders, and pipes are reported, never
/// followed or opened for reading), at most `maximumFileSize` bytes, and UTF-8. The folder
/// itself may be a symbolic link (a themes folder kept elsewhere). A file that fails any
/// check becomes a `CustomThemeFailure` the picker shows; it never stops the others loading.
/// A missing folder is simply empty.
public struct CustomThemeFolder: Sendable {
    /// The largest theme file read. Bundled themes are under 64 KB; this leaves room for
    /// `data:` images.
    public static let maximumFileSize = 512 * 1024
    /// The most theme files loaded, in file name order. The rest are reported once.
    public static let maximumThemeCount = 100
    /// The file extension of theme files (compared case-insensitively).
    public static let fileExtension = "css"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The theme file names in the folder, in load order (Finder's name order): visible
    /// `*.css` entries, whatever they are. Empty when the folder is missing or unreadable.
    public func themeFileNames() -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)) else {
            return []
        }
        return Self.sortedThemeFileNames(names)
    }

    private static func sortedThemeFileNames(_ names: [String]) -> [String] {
        names.filter(isThemeFileName).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Whether `name` names a theme file: not hidden, extension `css`.
    public static func isThemeFileName(_ name: String) -> Bool {
        !name.hasPrefix(".") && (name as NSString).pathExtension.lowercased() == fileExtension
            && name.count > fileExtension.count + 1
    }

    /// Reads every theme in the folder. `base` supplies the themes `extends` may name.
    public func load(base: ThemeRegistry = .bundled) -> CustomThemeCatalog {
        var catalog = CustomThemeCatalog()
        var isDirectory: ObjCBool = false
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return catalog
        }
        guard isDirectory.boolValue else {
            catalog.failures.append(
                CustomThemeFailure(fileName: url.lastPathComponent, problem: .notRegularFile, isFolder: true))
            return catalog
        }
        let names: [String]
        do {
            names = Self.sortedThemeFileNames(try FileManager.default.contentsOfDirectory(atPath: path))
        } catch {
            catalog.failures.append(
                CustomThemeFailure(
                    fileName: url.lastPathComponent, problem: .unreadable(reason: Self.reason(error)), isFolder: true))
            return catalog
        }
        for name in names.prefix(Self.maximumThemeCount) {
            do throws(CustomThemeProblem) {
                let css = try Self.readTheme(at: url.appending(path: name, directoryHint: .notDirectory))
                catalog.themes.append(try CustomTheme.make(fileName: name, css: css, base: base))
            } catch {
                catalog.failures.append(CustomThemeFailure(fileName: name, problem: error))
            }
        }
        if names.count > Self.maximumThemeCount {
            catalog.failures.append(
                CustomThemeFailure(
                    fileName: url.lastPathComponent, problem: .tooManyThemes(limit: Self.maximumThemeCount),
                    isFolder: true))
        }
        catalog.themes.sort {
            switch $0.displayName.localizedStandardCompare($1.displayName) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id < $1.id
            }
        }
        return catalog
    }

    /// The text of the theme file at `url`: a regular file (not followed if it is a symbolic
    /// link), at most `limit` bytes, UTF-8 without NULs. A leading byte order mark is dropped.
    public static func readTheme(at url: URL, limit: Int = maximumFileSize) throws(CustomThemeProblem) -> String {
        // O_NONBLOCK: opening a pipe named *.css must not wait for a writer.
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            throw code == ELOOP ? .symbolicLink : .unreadable(reason: String(cString: strerror(code)))
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw .unreadable(reason: String(cString: strerror(errno)))
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            throw .notRegularFile
        }
        guard info.st_size <= limit else {
            throw .tooLarge(bytes: Int(clamping: info.st_size), limit: limit)
        }

        // Read at most one byte past the limit: the file may have grown since `fstat`.
        var bytes = [UInt8](repeating: 0, count: limit + 1)
        var count = 0
        while count < bytes.count {
            let result = bytes.withUnsafeMutableBytes { buffer in
                read(descriptor, buffer.baseAddress.map { $0 + count }, buffer.count - count)
            }
            if result < 0 {
                if errno == EINTR {
                    continue
                }
                throw .unreadable(reason: String(cString: strerror(errno)))
            }
            if result == 0 {
                break
            }
            count += result
        }
        guard count <= limit else {
            throw .tooLarge(bytes: count, limit: limit)
        }
        return try decode(bytes[..<count])
    }

    /// `bytes` as theme text: UTF-8, no NULs, without a leading byte order mark.
    public static func decode(_ bytes: ArraySlice<UInt8>) throws(CustomThemeProblem) -> String {
        guard !bytes.contains(0) else {
            throw .containsNUL
        }
        let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? bytes.dropFirst(3) : bytes
        guard let text = String(validating: body, as: UTF8.self) else {
            throw .notUTF8
        }
        return text
    }

    private static func reason(_ error: any Error) -> String {
        ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription
            ?? error.localizedDescription
    }
}

/// What a scan of the themes folder found: the themes that loaded, sorted by name, and the
/// files that didn't, with why.
public struct CustomThemeCatalog: Sendable, Equatable {
    public var themes: [Theme]
    public var failures: [CustomThemeFailure]

    public init(themes: [Theme] = [], failures: [CustomThemeFailure] = []) {
        self.themes = themes
        self.failures = failures
    }

    /// No custom themes and nothing wrong.
    public static let empty = CustomThemeCatalog()
}

/// A theme file that didn't load, or a problem with the folder itself.
public struct CustomThemeFailure: Sendable, Equatable, Identifiable {
    /// The file (or, for `isFolder`, the folder) name.
    public var fileName: String
    public var problem: CustomThemeProblem
    /// Whether the problem is the folder's (unreadable, too many themes) rather than a file's.
    public var isFolder: Bool

    public init(fileName: String, problem: CustomThemeProblem, isFolder: Bool = false) {
        self.fileName = fileName
        self.problem = problem
        self.isFolder = isFolder
    }

    public var id: String { (isFolder ? "folder:" : "file:") + fileName }

    /// The name to show: the file's theme name from its file name (a failed file's header
    /// isn't trusted), or "Themes folder".
    public var displayName: String {
        isFolder ? "Themes folder" : CustomTheme.displayName(forFileName: fileName)
    }

    /// One line for the picker, e.g. "Solarized: @import isn’t allowed (line 3)".
    public var message: String {
        "\(displayName): \(problem)"
    }
}
