import Foundation
import PeepCLIKit
import PeepCore
import Testing

/// `--theme`, `--flavor`, and the list modes (#64). Custom themes come from a temp Themes folder
/// passed to the harness, never the reader's.
@Suite("Theme and flavor flags")
struct ThemeFlavorTests {
    private static let strikethrough = "~~gone~~\n"
    private static let validTheme = "/* peep-theme\n   name: Test Theme\n*/\nbody { color: #123456; }\n"

    /// A temp Themes folder holding `files` (name to CSS).
    private static func themesFolder(_ files: [String: String]) throws -> TempFolder {
        let folder = try TempFolder()
        for (name, css) in files {
            try folder.file(name, css)
        }
        return folder
    }

    // MARK: Flavor

    @Test("--flavor picks each bundled flavor's syntax", arguments: [("gfm", true), ("commonmark", false)])
    func flavors(id: String, strikes: Bool) async {
        let result = await CLIHarness.run(["--fragment", "--flavor", id], stdin: Self.strikethrough)
        #expect(result.status == 0)
        #expect(result.stdout.contains("<del>gone</del>") == strikes)
    }

    @Test("--flavor ids are case-insensitive")
    func flavorCase() async {
        let result = await CLIHarness.run(["--fragment", "--flavor", "CommonMark"], stdin: Self.strikethrough)
        #expect(result.status == 0)
        #expect(!result.stdout.contains("<del>"))
    }

    @Test("an unknown --flavor is a usage error listing the flavors")
    func unknownFlavor() async {
        let result = await CLIHarness.run(["--html", "--flavor", "markdown"], stdin: "x")
        #expect(result.status == 64)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Unknown flavor 'markdown'; use one of: gfm, commonmark."))
    }

    @Test(
        "--flavor beats the document's peep.flavor, in both directions",
        arguments: [("commonmark", "gfm", true), ("gfm", "commonmark", false)])
    func flavorBeatsFrontmatter(document: String, flag: String, strikes: Bool) async {
        let source = "---\npeep:\n  flavor: \(document)\n  wikilinks: true\n---\n\(Self.strikethrough)\n[[#Top]]\n"
        let result = await CLIHarness.run(["--fragment", "--flavor", flag], stdin: source)
        #expect(result.status == 0)
        #expect(result.stdout.contains("<del>gone</del>") == strikes)
        // The document's other overrides still apply.
        #expect(result.stdout.contains("class=\"wikilink\""))
    }

    @Test("without --flavor, the document's peep.flavor applies")
    func frontmatterFlavor() async {
        let result = await CLIHarness.run(
            ["--fragment"], stdin: "---\npeep: { flavor: commonmark }\n---\n\(Self.strikethrough)")
        #expect(result.status == 0)
        #expect(!result.stdout.contains("<del>"))
    }

    // MARK: Theme

    @Test("--theme picks each bundled theme", arguments: ThemeRegistry.bundled.themes.map(\.id))
    func bundledThemes(id: String) async {
        let result = await CLIHarness.run(["--html", "--theme", id], stdin: "# Hi\n")
        let theme = ThemeRegistry.bundled.theme(id: id)
        #expect(result.status == 0)
        #expect(result.stdout.contains(theme.layerCSS))
    }

    @Test("bundled --theme ids are case-insensitive")
    func themeCase() async {
        let result = await CLIHarness.run(["--html", "--theme", "Serif"], stdin: "# Hi\n")
        #expect(result.status == 0)
        #expect(result.stdout.contains(Theme.serif.layerCSS))
    }

    @Test("an unknown --theme is a usage error listing the themes")
    func unknownTheme() async {
        let result = await CLIHarness.run(["--html", "--theme", "solarized"], stdin: "x")
        #expect(result.status == 64)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Unknown theme 'solarized'; use one of: github, document, serif"))
    }

    @Test("--theme custom:<file> loads the theme from the Themes folder")
    func customTheme() async throws {
        let themes = try Self.themesFolder(["Test.css": Self.validTheme])
        let result = await CLIHarness.run(
            ["--html", "--theme", "custom:Test.css"], stdin: Data("# Hi\n".utf8), themesFolder: themes.url)
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("body { color: #123456; }"))
    }

    @Test("a custom --theme that isn't in the folder exits 66 naming the folder")
    func missingCustomTheme() async throws {
        let themes = try Self.themesFolder(["Test.css": Self.validTheme])
        let result = await CLIHarness.run(
            ["--html", "--theme", "custom:test.css"], stdin: Data("# Hi\n".utf8), themesFolder: themes.url)
        #expect(result.status == 66)
        #expect(result.stdout.isEmpty)
        let folder = themes.url.path(percentEncoded: false)
        #expect(result.stderr == "peep: theme \"custom:test.css\": no test.css in the Themes folder (\(folder))\n")
    }

    @Test("a custom --theme with no Themes folder exits 66")
    func noThemesFolder() async {
        let result = await CLIHarness.run(["--html", "--theme", "custom:Test.css"], stdin: "# Hi\n")
        #expect(result.status == 66)
        #expect(result.stderr == "peep: theme \"custom:Test.css\": no Test.css in the Themes folder\n")
    }

    @Test("a custom --theme that fails its checks exits 65 with the reason")
    func invalidCustomTheme() async throws {
        let themes = try Self.themesFolder(["Bad.css": "@import url(other.css);\n"])
        let result = await CLIHarness.run(
            ["--html", "--theme", "custom:Bad.css"], stdin: Data("# Hi\n".utf8), themesFolder: themes.url)
        #expect(result.status == 65)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "peep: theme \"custom:Bad.css\": @import isn’t allowed (line 1)\n")
    }

    @Test("a custom id is matched against the folder's files, never read as a path")
    func customThemeIsNotAPath() async throws {
        let outside = try Self.themesFolder(["Outside.css": Self.validTheme])
        let themes = try TempFolder()
        let escape = "custom:../\(outside.url.lastPathComponent)/Outside.css"
        let result = await CLIHarness.run(
            ["--html", "--theme", escape], stdin: Data("# Hi\n".utf8), themesFolder: themes.url)
        #expect(result.status == 66)
        #expect(!result.stdout.contains("#123456"))
    }

    @Test("--theme beats the document's peep.theme")
    func themeBeatsFrontmatter() async throws {
        let folder = try TempFolder()
        let result = await CLIHarness.run(["--html", "--theme", "document", try folder.fixture("serif-theme.md")])
        #expect(result.status == 0)
        #expect(result.stdout.contains(Theme.document.layerCSS))
        #expect(!result.stdout.contains(Theme.serif.layerCSS))
    }

    @Test("a custom --theme beats a bundled peep.theme, and a bundled one beats a custom peep.theme")
    func themePrecedenceBothWays() async throws {
        let themes = try Self.themesFolder(["Test.css": Self.validTheme])
        let serifDocument = Data("---\npeep: { theme: serif }\n---\n# Hi\n".utf8)
        let custom = await CLIHarness.run(
            ["--html", "--theme", "custom:Test.css"], stdin: serifDocument, themesFolder: themes.url)
        #expect(custom.stdout.contains("#123456"))
        #expect(!custom.stdout.contains(Theme.serif.layerCSS))

        let customDocument = Data("---\npeep: { theme: \"custom:Test.css\" }\n---\n# Hi\n".utf8)
        let bundled = await CLIHarness.run(
            ["--html", "--theme", "serif"], stdin: customDocument, themesFolder: themes.url)
        #expect(bundled.stdout.contains(Theme.serif.layerCSS))
        #expect(!bundled.stdout.contains("#123456"))
    }

    @Test("without --theme, a custom peep.theme loads from the Themes folder")
    func frontmatterCustomTheme() async throws {
        let themes = try Self.themesFolder(["Test.css": Self.validTheme])
        let result = await CLIHarness.run(
            ["--html"], stdin: Data("---\npeep: { theme: \"custom:Test.css\" }\n---\n# Hi\n".utf8),
            themesFolder: themes.url)
        #expect(result.status == 0)
        #expect(result.stdout.contains("#123456"))
    }

    @Test(
        "a document's unknown, missing, or invalid theme falls back to GitHub silently",
        arguments: ["solarized", "custom:Missing.css", "custom:Bad.css"])
    func frontmatterThemeFallback(id: String) async throws {
        let themes = try Self.themesFolder(["Bad.css": "@import url(other.css);\n"])
        let result = await CLIHarness.run(
            ["--html"], stdin: Data("---\npeep: { theme: \"\(id)\" }\n---\n# Hi\n".utf8), themesFolder: themes.url)
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains(Theme.github.layerCSS))
    }

    // MARK: Lists

    @Test("--list-flavors prints one id and name per line, default first")
    func listFlavors() async {
        let result = await CLIHarness.run(["--list-flavors"], stdinIsTerminal: true)
        #expect(result.status == 0)
        #expect(result.stdout == "gfm\tGitHub Flavored Markdown\ncommonmark\tCommonMark\n")
    }

    @Test("--list-themes prints bundled then custom themes; files that don't load go to stderr")
    func listThemes() async throws {
        let themes = try Self.themesFolder(["Test.css": Self.validTheme, "Bad.css": "@import url(x.css);\n"])
        let result = await CLIHarness.run(["--list-themes"], stdinIsTerminal: true, themesFolder: themes.url)
        #expect(result.status == 0)
        #expect(result.stdout == "github\tGitHub\ndocument\tDocument\nserif\tSerif\ncustom:Test.css\tTest Theme\n")
        #expect(result.stderr == "peep: custom:Bad.css: @import isn’t allowed (line 1)\n")
    }

    @Test("the list modes take no FILE, and only one at a time")
    func listUsage() async {
        let withFile = await CLIHarness.run(["--list-themes", "README.md"])
        #expect(withFile.status == 64)
        #expect(withFile.stderr.contains("take no FILE"))
        let both = await CLIHarness.run(["--list-themes", "--list-flavors"])
        #expect(both.status == 64)
    }
}

/// `ThemeResolver`, which `peep FILE --theme` (#67) reuses.
@Suite("Theme resolver")
struct ThemeResolverTests {
    @Test("PEEP_THEMES_FOLDER overrides the Themes folder; otherwise it is under Application Support")
    func themesFolder() {
        let override = ThemeResolver.themesFolder(environment: ["PEEP_THEMES_FOLDER": "/tmp/themes"])
        #expect(override?.path(percentEncoded: false) == "/tmp/themes/")
        let standard = ThemeResolver.themesFolder(environment: ["PEEP_THEMES_FOLDER": ""])
        #expect(standard?.path(percentEncoded: false).hasSuffix("/Library/Application Support/Peep/Themes/") == true)
    }

    @Test("errors carry their exit status")
    func errors() throws {
        let resolver = ThemeResolver(themesFolder: nil)
        #expect(throws: ThemeResolutionError.unknown(id: "nope")) { try resolver.theme(id: "nope") }
        #expect(ThemeResolutionError.unknown(id: "x").exitStatus == 64)
        #expect(try resolver.theme(id: "GitHub") == .github)
        #expect(resolver.documentTheme(id: nil) == .github)
        #expect(resolver.documentTheme(id: "custom:x.css") == .github)
    }
}
