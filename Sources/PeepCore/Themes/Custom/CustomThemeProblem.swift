/// Why a custom theme file (#35) wasn't loaded. The theme picker shows `description` as a
/// disabled item, so every case reads as a short sentence a theme author can act on.
public enum CustomThemeProblem: Error, Sendable, Equatable, CustomStringConvertible {
    /// The file couldn't be opened or read (`reason` is the system's message).
    case unreadable(reason: String)
    /// A symbolic link: themes are read only from regular files inside the folder.
    case symbolicLink
    /// A folder, pipe, or other non-file named `*.css`.
    case notRegularFile
    /// Over `CustomThemeFolder.maximumFileSize`.
    case tooLarge(bytes: Int, limit: Int)
    /// Not valid UTF-8.
    case notUTF8
    /// Contains a NUL byte (a binary file).
    case containsNUL
    /// The folder holds more theme files than `CustomThemeFolder.maximumThemeCount`.
    case tooManyThemes(limit: Int)

    // Header (`/* peep-theme … */`)

    /// A header line that isn't `key: value`, or a value that isn't valid for its key.
    case invalidHeader(line: Int, message: String)
    /// `extends:` names no bundled theme.
    case unknownBaseTheme(String)

    // CSS

    /// An `@import` rule: themes are one self-contained file.
    case importRule(line: Int)
    /// A `url()` (or `image-set()`, `src()`, `image()` string) that isn't a `data:image/…` URL.
    case externalURL(line: Int)
    /// `expression()`: never valid in WebKit, rejected rather than passed on.
    case expression(line: Int)
    /// A closing bracket with no matching opener (a stray `}` would escape the theme's layer).
    case unexpectedClose(String, line: Int)
    /// An opening bracket that is never closed.
    case unclosed(String, line: Int)
    /// A `/*` comment that never ends.
    case unterminatedComment(line: Int)
    /// A string that ends at a line break or the end of the file.
    case unterminatedString(line: Int)

    public var description: String {
        switch self {
        case .unreadable(let reason): "Can’t be read: \(reason)"
        case .symbolicLink: "Symbolic links aren’t loaded; copy the file into the Themes folder"
        case .notRegularFile: "Not a regular file"
        case .tooLarge(let bytes, let limit):
            "Too large (\(Self.kilobytes(bytes)); the limit is \(Self.kilobytes(limit)))"
        case .notUTF8: "Not UTF-8 text"
        case .containsNUL: "Contains NUL bytes; not a text file"
        case .tooManyThemes(let limit): "More than \(limit) themes; the rest aren’t loaded"
        case .invalidHeader(let line, let message): "\(message) (line \(line))"
        case .unknownBaseTheme(let id): "“extends: \(id)” names no bundled theme"
        case .importRule(let line): "@import isn’t allowed (line \(line))"
        case .externalURL(let line): "Only data:image URLs are allowed in url() (line \(line))"
        case .expression(let line): "expression() isn’t allowed (line \(line))"
        case .unexpectedClose(let bracket, let line): "Unmatched “\(bracket)” (line \(line))"
        case .unclosed(let bracket, let line): "“\(bracket)” is never closed (line \(line))"
        case .unterminatedComment(let line): "Comment is never closed (line \(line))"
        case .unterminatedString(let line): "String is never closed (line \(line))"
        }
    }

    private static func kilobytes(_ bytes: Int) -> String {
        "\((bytes + 1023) / 1024) KB"
    }
}
