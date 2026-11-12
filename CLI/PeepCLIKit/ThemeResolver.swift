import Foundation
import PeepCore

/// Turns theme ids into themes for the CLI (#64): a bundled id (`github`, compared lowercased) or
/// `custom:<file name>` from the Themes folder. `--theme` and `peep FILE --theme` (#67) use
/// `theme(id:)`, which fails with a reason; a document's `peep.theme` uses `documentTheme(id:)`,
/// which falls back to GitHub silently because documents are untrusted.
///
/// Custom themes load through `CustomThemeFolder` with the same checks as the app's
/// (`CustomThemeCSS`). An id is only ever matched against the themes the folder holds, never
/// turned into a path, so `custom:../x.css` can't name a file outside it.
public struct ThemeResolver: Sendable {
    /// The environment variable that overrides the Themes folder (tests, or themes kept
    /// elsewhere).
    public static let themesFolderVariable = "PEEP_THEMES_FOLDER"

    /// The bundled themes, which `extends:` may name and which no custom theme can shadow.
    public static let base = ThemeRegistry.bundled

    /// Where custom themes are read from; `nil` reads none.
    public let themesFolder: URL?

    public init(themesFolder: URL?) {
        self.themesFolder = themesFolder
    }

    /// The Themes folder for this process: `PEEP_THEMES_FOLDER` when set and not empty (relative
    /// paths resolve against the working directory), else the app's
    /// `~/Library/Application Support/Peep/Themes` (`CustomThemeLibrary.folderURL`).
    public static func themesFolder(environment: [String: String]) -> URL? {
        if let path = environment[themesFolderVariable], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).absoluteURL
        }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return nil
        }
        return
            support
            .appending(path: "Peep", directoryHint: .isDirectory)
            .appending(path: "Themes", directoryHint: .isDirectory)
    }

    /// What the Themes folder holds: the themes that load and the files that don't. Empty with
    /// no folder. Reads the folder each call.
    public func customThemes() -> CustomThemeCatalog {
        guard let themesFolder else {
            return .empty
        }
        return CustomThemeFolder(url: themesFolder).load(base: Self.base)
    }

    /// The theme `id` names, or why it can't be used. Bundled ids are compared lowercased;
    /// `custom:` ids exactly (file names are case-sensitive). Reads the folder only for a
    /// `custom:` id.
    public func theme(id: String) throws(ThemeResolutionError) -> Theme {
        guard id.hasPrefix(CustomTheme.idPrefix) else {
            let bundledID = id.lowercased()
            guard Self.base.contains(id: bundledID) else {
                throw .unknown(id: id)
            }
            return Self.base.theme(id: bundledID)
        }
        let catalog = customThemes()
        if let theme = catalog.themes.first(where: { $0.id == id }) {
            return theme
        }
        if let failure = catalog.failures.first(where: {
            !$0.isFolder && CustomTheme.id(forFileName: $0.fileName) == id
        }) {
            throw .invalid(id: id, problem: failure.problem)
        }
        let folderProblem = catalog.failures.first(where: \.isFolder)?.problem
        throw .notFound(id: id, folder: themesFolder?.path(percentEncoded: false), folderProblem: folderProblem)
    }

    /// A document's `peep.theme` (already normalized by `DocumentOverrides`): the theme it names
    /// when it resolves, else the default (GitHub). Never fails.
    public func documentTheme(id: String?) -> Theme {
        guard let id else {
            return Self.base.defaultTheme
        }
        return (try? theme(id: id)) ?? Self.base.defaultTheme
    }

    /// Bundled ids as `--help` and errors list them.
    static var bundledIDs: String {
        base.themes.map(\.id).joined(separator: ", ")
    }

    /// Whether `id` could name a theme without reading the folder: a bundled id, or any
    /// `custom:` id (checked when it is resolved). For argument validation.
    static func isPlausible(_ id: String) -> Bool {
        id.hasPrefix(CustomTheme.idPrefix) ? id.count > CustomTheme.idPrefix.count : base.contains(id: id.lowercased())
    }
}

/// Why `ThemeResolver.theme(id:)` couldn't resolve an id. `description` is one line naming the id
/// and the reason; `exitStatus` is what the CLI exits with.
public enum ThemeResolutionError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Not a bundled id and not `custom:<file name>`.
    case unknown(id: String)
    /// No theme file with that name in the Themes folder (`folder` is nil with no folder);
    /// `folderProblem` when the folder itself couldn't be read or had too many themes.
    case notFound(id: String, folder: String?, folderProblem: CustomThemeProblem?)
    /// The file is there but isn't a valid theme (`CustomThemeCSS`, size, encoding, ...).
    case invalid(id: String, problem: CustomThemeProblem)

    public var description: String {
        switch self {
        case .unknown(let id):
            return "unknown theme \"\(Self.shortened(id))\"; use \(ThemeResolver.bundledIDs), "
                + "or custom:<file name> (peep --list-themes)"
        case .notFound(let id, let folder, let folderProblem):
            let fileName = String(id.dropFirst(CustomTheme.idPrefix.count))
            var message = "theme \"\(Self.shortened(id))\": no \(Self.shortened(fileName)) in the Themes folder"
            if let folder {
                message += " (\(folder))"
            }
            if let folderProblem {
                message += ": \(folderProblem)"
            }
            return message
        case .invalid(let id, let problem):
            return "theme \"\(Self.shortened(id))\": \(problem)"
        }
    }

    /// 64 for an id that names nothing Peep knows, 66 for a missing theme file (like a missing
    /// input), 65 for a theme file that fails its checks (like an input that isn't UTF-8).
    public var exitStatus: Int32 {
        switch self {
        case .unknown: ExitStatus.usage
        case .notFound: ExitStatus.noInput
        case .invalid: ExitStatus.dataError
        }
    }

    /// The error as the CLI reports it.
    public var cliError: CLIError {
        CLIError(description, status: exitStatus)
    }

    private static func shortened(_ text: String) -> String {
        text.count > 80 ? "\(text.prefix(80))…" : text
    }
}
