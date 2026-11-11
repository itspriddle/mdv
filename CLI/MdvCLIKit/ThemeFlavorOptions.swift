import ArgumentParser
import Foundation
import MdvCore

/// `--theme`, `--flavor`, `--list-themes`, and `--list-flavors` (#64). Used by headless output
/// and, for `--theme`, by `mdv FILE` in the app (#67 reads this group from
/// `MdvCommand.themeFlavor` and resolves it with `ThemeResolver`).
///
/// Precedence, as for a window's View > Theme pick: a flag beats the document's `mdv:`
/// frontmatter, which beats the default (GitHub, GFM).
public struct ThemeFlavorOptions: ParsableArguments, Sendable {
    @Option(
        help: ArgumentHelp(
            "The page's theme: \(ThemeResolver.bundledIDs), or custom:<file name> from the "
                + "Themes folder. Beats the document's mdv.theme.",
            valueName: "NAME"))
    public var theme: String?

    @Option(
        help: ArgumentHelp(
            "The Markdown flavor: \(ThemeFlavorOptions.flavorIDs). Beats the document's mdv.flavor.",
            valueName: "NAME"))
    public var flavor: String?

    @Flag(help: "List theme ids and names (bundled, then the Themes folder's), then exit.")
    public var listThemes = false

    @Flag(help: "List flavor ids and names, then exit.")
    public var listFlavors = false

    public init() {}

    public func validate() throws {
        if let flavor, !FlavorRegistry.bundled.contains(id: flavor.lowercased()) {
            throw ValidationError("Unknown flavor '\(flavor)'; use one of: \(Self.flavorIDs).")
        }
        if let theme, !ThemeResolver.isPlausible(theme) {
            throw ValidationError(
                "Unknown theme '\(theme)'; use one of: \(ThemeResolver.bundledIDs), or custom:<file name> "
                    + "(see --list-themes).")
        }
        if listThemes, listFlavors {
            throw ValidationError("Pass --list-themes or --list-flavors, not both.")
        }
    }

    /// Whether this run only lists themes or flavors (reads no input).
    var lists: Bool { listThemes || listFlavors }

    /// The `--flavor` flag's flavor, when given (validated in `validate()`).
    public var flavorChoice: Flavor? {
        flavor.map { FlavorRegistry.bundled.flavor(id: $0.lowercased()) }
    }

    /// Sets `--flavor` and pins it, so the document's `mdv.flavor` doesn't replace it.
    func apply(to options: inout RenderOptions) {
        guard let flavorChoice else {
            return
        }
        options.flavor = flavorChoice
        options.pinnedOverrides.insert(.flavor)
    }

    /// The page's theme for `--html`: `--theme` (an error when it can't be used), else the
    /// document's `mdv.theme` when it resolves (bundled or custom), else GitHub.
    func theme(for rendered: RenderedDocument, in environment: CLIEnvironment) throws(CLIError) -> Theme {
        let resolver = ThemeResolver(themesFolder: environment.themesFolder)
        guard let theme else {
            return resolver.documentTheme(id: rendered.overrides.theme)
        }
        do {
            return try resolver.theme(id: theme)
        } catch {
            throw error.cliError
        }
    }

    /// Prints `--list-themes` or `--list-flavors`: one `id<TAB>name` line each, default first.
    /// Custom theme files that don't load are reported on standard error, one line each; they
    /// don't change the exit status.
    func list(in environment: CLIEnvironment) throws(CLIError) {
        var lines: [(id: String, name: String)]
        if listFlavors {
            lines = FlavorRegistry.bundled.flavors.map { ($0.id, $0.displayName) }
        } else {
            let custom = ThemeResolver(themesFolder: environment.themesFolder).customThemes()
            let registry = ThemeResolver.base.adding(custom.themes)
            lines = registry.themes.map { ($0.id, $0.displayName) }
            for failure in custom.failures {
                let subject = failure.isFolder ? "Themes folder" : CustomTheme.id(forFileName: failure.fileName)
                environment.reportError("\(subject): \(failure.problem)")
            }
        }
        let text = lines.map { "\($0.id)\t\($0.name)\n" }.joined()
        do {
            try environment.standardOutput.write(Data(text.utf8))
        } catch {
            throw CLIError("stdout: \(error.localizedDescription)", status: ExitStatus.ioError)
        }
    }

    private static var flavorIDs: String {
        FlavorRegistry.bundled.flavors.map(\.id).joined(separator: ", ")
    }
}
