import ArgumentParser
import Foundation
import PeepCore

/// Headless render options (#65): frontmatter display, wiki links, source lines, highlighting,
/// remote images, heading anchors, and frontmatter diagnostics.
///
/// Flags only: the CLI never reads the app's Settings > Markdown, so the same command gives the
/// same output whatever the app is set to. There is deliberately no `--no-sanitize` (VISION's
/// security model): raw HTML from an untrusted file, opened in a browser, would run its scripts.
public struct RenderFlagOptions: ParsableArguments, Sendable {
    /// How `--frontmatter` shows a document's frontmatter block.
    public enum FrontmatterChoice: String, CaseIterable, ExpressibleByArgument, Sendable {
        case hidden
        case table

        var display: FrontmatterDisplay {
            switch self {
            case .hidden: .hidden
            case .table: .table
            }
        }
    }

    @Option(
        help: ArgumentHelp(
            "How to show frontmatter: table puts it before the body (YAML as a table, TOML as code).",
            valueName: "MODE"))
    public var frontmatter: FrontmatterChoice = .hidden

    @Flag(
        inversion: .prefixedNo,
        help: "Turn [[wiki links]] on or off. Beats the document's peep.wikilinks (default: off).")
    public var wikiLinks: Bool?

    @Flag(help: "Add data-source-line attributes (the line each block starts on).")
    public var sourceLines = false

    @Flag(name: .customLong("no-highlight"), help: "Don't syntax-highlight fenced code blocks.")
    public var noHighlight = false

    @Flag(name: .customLong("no-heading-anchors"), help: "Don't give headings ids and anchor links.")
    public var noHeadingAnchors = false

    @Flag(help: "Replace remote images with a placeholder (default: keep them, as GitHub does).")
    public var blockRemoteImages = false

    @Flag(help: "Report the flavor and wiki link setting each input used, on standard error.")
    public var verbose = false

    public init() {}

    /// Whether any flag here was given. They change headless output only, so without `--html`,
    /// `--fragment`, or `--output` they are a usage error (`PeepCommand.validate()`).
    var isSet: Bool {
        frontmatter != .hidden || wikiLinks != nil || sourceLines || noHighlight || noHeadingAnchors
            || blockRemoteImages || verbose
    }

    /// Sets this group's `RenderOptions`. Without flags these are `RenderOptions`' defaults
    /// (frontmatter hidden, no wiki links, no `data-source-line`, highlighting and heading
    /// anchors on, remote images kept). `--wiki-links`/`--no-wiki-links` pin `.wikiLinks`, so
    /// the document's `peep.wikilinks` doesn't replace the flag.
    func apply(to options: inout RenderOptions) {
        options.frontmatterDisplay = frontmatter.display
        if let wikiLinks {
            if wikiLinks {
                options.builtInPreprocessors.insert(.wikiLinks)
            } else {
                options.builtInPreprocessors.remove(.wikiLinks)
            }
            options.pinnedOverrides.insert(.wikiLinks)
        }
        options.sourceLines = sourceLines
        options.highlighting = !noHighlight
        options.headingAnchors = !noHeadingAnchors
        if blockRemoteImages {
            options.remoteImages = .block
        }
    }

    /// The renderer for one input. A file resolves root-relative URLs (`/docs/x.png`) and wiki
    /// links as the app does: against its allowed root (`LocalResourceRoot`, the git work tree
    /// or its folder), searching its own folder first. Standard input has neither, so page
    /// links render as missing (`[[#Heading]]` still works) and root-relative URLs stay as written.
    func renderer(options: RenderOptions, for source: InputSource) -> HTMLRenderer {
        guard let url = source.url else {
            return HTMLRenderer(options: options)
        }
        var options = options
        let root = LocalResourceRoot.forDocument(at: url)
        options.linkRoot = root
        return HTMLRenderer(
            options: options, wikiLinkResolver: FolderWikiLinkResolver.fileSystem(forDocumentAt: url, root: root))
    }

    /// Reports what a render noticed on standard error, never standard output: frontmatter
    /// `peep:` keys it ignored and why (always), and with `--verbose` the flavor and wiki link
    /// setting used and where each came from. `options` are the options before the document's
    /// overrides (what `apply(to:)` set).
    func report(
        _ rendered: RenderedDocument, options: RenderOptions, for source: InputSource, in environment: CLIEnvironment
    ) {
        for line in diagnostics(rendered, options: options) {
            environment.reportError(Self.terminalSafe("\(source.displayName): \(line)"))
        }
    }

    /// The lines `report` prints, without the `peep: <input>: ` prefix.
    func diagnostics(_ rendered: RenderedDocument, options: RenderOptions) -> [String] {
        var lines: [String] = []
        if verbose {
            lines.append("flavor \(rendered.flavor.id) (\(flavorOrigin(rendered, options: options)))")
            lines.append(wikiLinksLine(rendered.overrides, options: options))
        }
        lines += rendered.overrides.ignored.map { "warning: \($0.description)" }
        return lines
    }

    private func flavorOrigin(_ rendered: RenderedDocument, options: RenderOptions) -> String {
        let asked = rendered.overrides.flavor
        if options.pinnedOverrides.contains(.flavor) {
            if let asked, asked != rendered.flavor.id {
                return "--flavor; the document's peep.flavor \(asked) wasn't used"
            }
            return "--flavor"
        }
        return asked == rendered.flavor.id ? "the document's peep.flavor" : "default"
    }

    private func wikiLinksLine(_ overrides: DocumentOverrides, options: RenderOptions) -> String {
        let flag = options.builtInPreprocessors.contains(.wikiLinks)
        var origin: String
        let isOn: Bool
        if options.pinnedOverrides.contains(.wikiLinks) {
            isOn = flag
            origin = flag ? "--wiki-links" : "--no-wiki-links"
            if let document = overrides.wikiLinks, document != flag {
                origin += "; the document's peep.wikilinks wasn't used"
            }
        } else if let document = overrides.wikiLinks {
            isOn = document
            origin = "the document's peep.wikilinks"
        } else {
            isOn = flag
            origin = "default"
        }
        return "wiki links \(isOn ? "on" : "off") (\(origin))"
    }

    /// `text` with control characters (C0, DEL, C1) written as `\u{XX}`, so a document's
    /// frontmatter keys can't send escape sequences to the reader's terminal.
    static func terminalSafe(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if scalar.properties.generalCategory == .control {
                result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
