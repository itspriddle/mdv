import Foundation
import Testing

@testable import PeepCore

/// Keeps the theme authoring guide (`docs/THEMES.md`, #44) honest: its example theme loads, its
/// CSS snippets pass the custom theme check, and the error messages and limits it quotes are
/// the ones Peep uses.
@Suite("Theme authoring guide")
struct ThemeGuideTests {
    static let docs = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(components: "..", "..", "docs")

    static func guide() throws -> String {
        try String(contentsOf: docs.appending(path: "THEMES.md"), encoding: .utf8)
    }

    static func exampleTheme() throws -> String {
        try String(contentsOf: docs.appending(path: "example-theme.css"), encoding: .utf8)
    }

    /// The contents of every ```css fence in `markdown`, without the fence's indentation.
    static func cssBlocks(in markdown: String) -> [String] {
        var blocks: [String] = []
        var current: [Substring]?
        var indent = 0
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " }
            if var lines = current {
                if trimmed.hasPrefix("```") {
                    blocks.append(lines.joined(separator: "\n"))
                    current = nil
                } else {
                    lines.append(line.dropFirst(min(indent, line.prefix { $0 == " " }.count)))
                    current = lines
                }
            } else if trimmed == "```css" {
                indent = line.count - trimmed.count
                current = []
            }
        }
        return blocks
    }

    @Test("the example theme loads from a Themes folder with its header's name and backgrounds")
    func exampleLoads() throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-theme-guide-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(try Self.exampleTheme().utf8).write(to: folder.appending(path: "Notebook.css"))

        let catalog = CustomThemeFolder(url: folder).load()
        #expect(catalog.failures.isEmpty, "\(catalog.failures.map(\.message))")
        let theme = try #require(catalog.themes.first)
        #expect(theme.id == "custom:Notebook.css")
        #expect(theme.displayName == "Notebook")
        #expect(theme.background == ThemeBackground(light: ThemeColor(0xFB_FA_F7), dark: ThemeColor(0x1C_1B_19)))
        #expect(theme.stylesheet.contains("var(\(UserStyle.contentWidthProperty), 44em)"))
        #expect(theme.layerCSS.hasPrefix("@layer \(ThemeLayer.theme.name) {"))
    }

    @Test("the GitHub Soft Dark example extends GitHub and loads with its dark background")
    func softDarkLoads() throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-theme-guide-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let css = try String(contentsOf: Self.docs.appending(path: "github-soft-dark.css"), encoding: .utf8)
        try Data(css.utf8).write(to: folder.appending(path: "github-soft-dark.css"))

        let catalog = CustomThemeFolder(url: folder).load()
        #expect(catalog.failures.isEmpty, "\(catalog.failures.map(\.message))")
        let theme = try #require(catalog.themes.first)
        #expect(theme.displayName == "GitHub Soft Dark")
        #expect(theme.background == ThemeBackground(light: ThemeColor(0xFF_FF_FF), dark: ThemeColor(0x21_28_30)))
        #expect(theme.stylesheet.contains(Theme.github.stylesheet), "starts from the GitHub theme")
        #expect(theme.stylesheet.contains("--bgColor-default: #212830;"))
    }

    @Test("the guide shows the example theme exactly as the file has it")
    func exampleInGuide() throws {
        let example = try Self.exampleTheme().trimmingCharacters(in: .newlines)
        #expect(try Self.cssBlocks(in: Self.guide()).contains(example))
    }

    @Test("every CSS snippet in the guide passes the custom theme check; themes with a header load")
    func snippetsPass() throws {
        let blocks = try Self.cssBlocks(in: Self.guide())
        #expect(blocks.count >= 5)
        for (index, css) in blocks.enumerated() {
            do throws(CustomThemeProblem) {
                if css.hasPrefix("/* \(CustomTheme.headerMarker)") {
                    _ = try CustomTheme.make(fileName: "snippet-\(index).css", css: css)
                } else {
                    try CustomThemeCSS.validate(css)
                }
            } catch {
                Issue.record("snippet \(index) is rejected: \(error)\n\(css)")
            }
            // Dark colors are screen only (paper prints light), as the guide tells authors.
            #expect(
                css.ranges(of: "prefers-color-scheme").count
                    == css.ranges(of: "screen and (prefers-color-scheme: dark)").count,
                "snippet \(index) has a dark rule without `screen and`")
        }
    }

    @Test("the guide quotes Peep's own messages for rejected themes")
    func errorMessages() throws {
        let guide = try Self.guide()
        func problem(_ css: String) -> CustomThemeProblem? {
            do throws(CustomThemeProblem) {
                _ = try CustomTheme.make(fileName: "t.css", css: css)
                return nil
            } catch {
                return error
            }
        }
        let problems: [CustomThemeProblem?] = [
            problem("@import \"base.css\";"),
            problem("p { background: url(paper.png); }"),
            problem("p { width: expression(1); }"),
            problem("p { color: red; } }"),
            problem("p { color: red;"),
            problem("/* never closed"),
            problem("p::before { content: \"x; }"),
            problem("/* peep-theme\nbackground: white\n*/"),
            problem("/* peep-theme\ncolour: red\n*/"),
            problem("/* peep-theme\nname: A\nname: B\n*/"),
            problem("/* peep-theme\njust text\n*/"),
            problem("/* peep-theme\nextends: GitHub\n*/"),
            .symbolicLink,
            .tooLarge(bytes: 600 * 1024, limit: CustomThemeFolder.maximumFileSize),
            .notUTF8,
            .containsNUL,
            .tooManyThemes(limit: CustomThemeFolder.maximumThemeCount),
        ]
        for problem in problems {
            let problem = try #require(problem)
            #expect(guide.contains("| \(problem.description) |"), "the guide doesn't quote “\(problem)”")
        }
    }

    @Test("the element table documents the alert markup Peep writes (#52)")
    func alertMarkup() throws {
        let guide = try Self.guide()
        let rendered = HTMLRenderer().render("> [!NOTE]\n> Body.\n").html
        #expect(guide.contains("`<div class=\"markdown-alert markdown-alert-note\">`"))
        #expect(
            rendered.hasPrefix(
                "<div class=\"markdown-alert markdown-alert-note\"><p class=\"markdown-alert-title\"><svg"))
        for type in GitHubAlert.allCases {
            #expect(guide.contains("`\(type.className)`") || guide.contains("\(type.className)\">`"), "\(type)")
        }
    }

    @Test("the guide's wiki link markup is what Peep writes (#53)")
    func wikiLinkMarkup() throws {
        let guide = try Self.guide()
        var options = RenderOptions()
        options.builtInPreprocessors = [.wikiLinks]
        let resolver = FakeWikiLinkResolver(["Page-Name.md"])
        let rendered = HTMLRenderer(options: options, wikiLinkResolver: resolver)
            .render("[[Page Name]]\n[[Missing Page]]").html
        let block = try #require(Self.htmlBlocks(in: guide).first { $0.contains("wikilink") })
        #expect("<p>" + block + "</p>\n" == rendered)
        #expect(ThemeBase.css.contains(".wikilink-missing {"))
    }

    @Test("the limits and values the guide states match Peep's")
    func limits() throws {
        let guide = try Self.guide()
        #expect(guide.contains("at most \(CustomThemeFolder.maximumFileSize / 1024) KB"))
        #expect(guide.contains("At most \(CustomThemeFolder.maximumThemeCount) themes"))
        #expect(guide.contains("at most \(CustomTheme.maximumNameLength) characters"))
        #expect(guide.contains("`\(UserStyle.contentWidthProperty)`"))
        let widths = ContentWidth.allCases.compactMap(\.cssValue).map { "`\($0)`" }
        #expect(guide.contains(widths.joined(separator: ", ") + ", or the custom width in `px`"))
        #expect(guide.contains("`box-sizing`\nto `content-box`"))
        for theme in ThemeRegistry.bundled.themes {
            #expect(guide.contains("`\(theme.id)`"))
        }
        #expect(guide.contains("`\(Theme.github.background.light.hex)`"))
        #expect(guide.contains("`\(Theme.github.background.dark.hex)`"))
    }

    /// The ```html fences in `markdown`.
    static func htmlBlocks(in markdown: String) -> [String] {
        markdown.components(separatedBy: "```html\n").dropFirst().compactMap {
            $0.components(separatedBy: "\n```").first
        }
    }

    @Test("the frontmatter markup the guide shows is what Peep renders (#55)")
    func frontmatterMarkup() throws {
        var options = RenderOptions()
        options.frontmatterDisplay = .table
        let renderer = HTMLRenderer(options: options)
        let yaml = renderer.render("---\ntitle: Release notes\n---\n").html
        let toml = renderer.render("+++\ntitle = \"Release notes\"\n+++\n").html
        // The guide unescapes quotes and drops the TOML block's trailing newline, for reading.
        let expected =
            yaml + "\n"
            + toml.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "\n</code>", with: "</code>")
        let blocks = Self.htmlBlocks(in: try Self.guide())
        #expect(blocks.contains(expected.trimmingCharacters(in: .newlines)), "\(expected)")
        #expect(try Self.guide().contains("Settings > Markdown > Frontmatter > Shown as a Table"))
    }
}
